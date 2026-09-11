import { createHmac, randomUUID } from 'node:crypto';
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';
import type { Environment } from '../config/env.js';
import { Database, audit, hash, type Actor, type Tx } from '../db/database.js';
import { AppError, ensure } from '../domain/errors.js';
import { userDto } from '../domain/mobile_dto.js';
import type { WalletService } from './wallet_service.js';

export interface VerifiedIdentity { issuer: string; subject: string; expiresAt: Date; tokenHash: string; claims: JWTPayload }
export interface Principal { userId: string; sessionId: string; role: 'user' | 'reviewer' | 'admin'; status: string; actor: Actor }

export class AuthService {
  private readonly jwks;
  constructor(readonly db: Database, readonly env: Environment, readonly wallet: WalletService) {
    this.jwks = env.jwksUrl ? createRemoteJWKSet(env.jwksUrl, { timeoutDuration: 5000, cooldownDuration: 30000, cacheMaxAge: 300000 }) : undefined;
  }
  signal(value: string): string { return createHmac('sha256', this.env.riskSecret()).update(value).digest('hex'); }
  async verify(header: string | undefined): Promise<VerifiedIdentity> {
    ensure(header && /^Bearer [\x21-\x7e]{16,8192}$/.test(header), 'unauthenticated', 401);
    const token = header.slice(7);
    try {
      const result = this.env.jwtMode === 'jwks'
        ? await jwtVerify(token, this.jwks!, { issuer: this.env.jwtIssuer, audience: this.env.jwtAudience, algorithms: ['RS256','ES256'], clockTolerance: 5 })
        : await jwtVerify(token, this.env.jwtSecret(), { issuer: this.env.jwtIssuer, audience: this.env.jwtAudience, algorithms: ['HS256'], clockTolerance: 0 });
      const claims = result.payload; const now = Math.floor(Date.now() / 1000);
      ensure(typeof claims.sub === 'string' && claims.sub.length > 0 && claims.sub.length <= 255 &&
        typeof claims.exp === 'number' && Number.isInteger(claims.exp) && typeof claims.iat === 'number' && Number.isInteger(claims.iat) &&
        claims.exp > now && claims.iat <= now + 30 && claims.exp - claims.iat <= this.env.maxTokenTtl, 'unauthenticated', 401);
      return { issuer: this.env.jwtIssuer, subject: claims.sub, expiresAt: new Date(claims.exp * 1000), tokenHash: hash(token), claims };
    } catch { throw new AppError('unauthenticated', 401); }
  }

  async openSession(identity: VerifiedIdentity, input: { displayName?: string; username?: string; referralCode?: string; deviceHint?: string }, actor: Actor) {
    return this.db.transaction(async tx => {
      await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`identity:${identity.issuer}:${identity.subject}`]);
      const used = (await tx.query('SELECT * FROM user_sessions WHERE token_hash=$1', [identity.tokenHash])).rows[0];
      ensure(!used?.revoked_at, 'unauthenticated', 401);
      let identityRow = (await tx.query('SELECT * FROM auth_identities WHERE issuer=$1 AND subject=$2', [identity.issuer, identity.subject])).rows[0];
      if (!identityRow) {
        ensure(this.env.registrationEnabled, 'restricted', 403);
        const id = randomUUID();
        await tx.query('INSERT INTO users(id,display_name,username,referral_code,development_only) VALUES($1,$2,$3,$4,$5)',
          [id, input.displayName ?? 'ShareBondhu user', input.username ?? `user_${id.replaceAll('-', '').slice(0,12)}`, `SB${id.replaceAll('-', '').slice(0,12)}`, this.env.name !== 'production']);
        await this.wallet.createWallet(tx, id);
        identityRow = (await tx.query('INSERT INTO auth_identities(user_id,issuer,subject) VALUES($1,$2,$3) RETURNING *', [id,identity.issuer,identity.subject])).rows[0];
        if (input.referralCode) {
          const inviter = (await tx.query('SELECT id FROM users WHERE referral_code=$1 AND status=\'active\'', [input.referralCode])).rows[0];
          ensure(inviter && inviter.id !== id, 'invalid_request');
          await tx.query('INSERT INTO referrals(inviter_id,invitee_id) VALUES($1,$2)', [inviter.id,id]);
        }
        await audit(tx, actor, id, 'account.create', 'user', id, 'Account created from a cryptographically verified configured issuer. Opening balance is zero.');
      }
      const user = (await tx.query('SELECT * FROM users WHERE id=$1', [identityRow.user_id])).rows[0];
      ensure(!['suspended','deleted'].includes(user.status), 'restricted', 403);
      const deviceHash = input.deviceHint ? this.signal(`device:${input.deviceHint}`) : null;
      const session = used ?? (await tx.query('INSERT INTO user_sessions(user_id,identity_id,token_hash,expires_at,ip_hash,device_hash) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',
        [user.id,identityRow.id,identity.tokenHash,identity.expiresAt,actor.ipHash ?? null,deviceHash])).rows[0];
      await tx.query('UPDATE users SET last_active_at=now(),version=version+1 WHERE id=$1', [user.id]);
      if (actor.ipHash || deviceHash) await this.recordSharedSignals(tx, user.id, actor.ipHash, deviceHash ?? undefined);
      await audit(tx, { kind: 'user', id: user.id, userId: user.id, requestId: actor.requestId }, user.id, 'auth.session', 'session', session.id, 'Verified token registered. No raw token stored.');
      return { user: userDto((await tx.query('SELECT * FROM users WHERE id=$1', [user.id])).rows[0]), sessionId: session.id,
        expiresAt: identity.expiresAt.toISOString(), authentication: this.env.jwtMode === 'development_hmac' ? 'development_hmac' : 'configured_jwks' };
    });
  }

  private async recordSharedSignals(tx: Tx, userId: string, ipHash?: string, deviceHash?: string) {
    const shared = (await tx.query('SELECT count(DISTINCT user_id)::int AS accounts FROM user_sessions WHERE user_id<>$1 AND ((ip_hash=$2 AND $2 IS NOT NULL) OR (device_hash=$3 AND $3 IS NOT NULL))',
      [userId,ipHash ?? null,deviceHash ?? null])).rows[0].accounts;
    if (shared > 0) await tx.query("INSERT INTO risk_flags(user_id,code,blocking,context) VALUES($1,'shared_signal',false,$2) ON CONFLICT(user_id,code) DO UPDATE SET active=true,context=EXCLUDED.context", [userId,{ linkedAccounts: shared, note: 'Risk signal only, not proof of fraud.' }]);
  }

  async authenticate(header: string | undefined, requestId: string, ip: string, write = false): Promise<Principal> {
    const identity = await this.verify(header);
    const session = (await this.db.query(`SELECT s.*,u.role,u.status FROM user_sessions s JOIN auth_identities a ON a.id=s.identity_id JOIN users u ON u.id=s.user_id
      WHERE s.token_hash=$1 AND a.issuer=$2 AND a.subject=$3 AND s.revoked_at IS NULL AND s.expires_at>now()`, [identity.tokenHash,identity.issuer,identity.subject])).rows[0];
    ensure(session, 'unauthenticated', 401);
    ensure(!['suspended','deleted'].includes(session.status) && (!write || session.status === 'active'), 'restricted', 403);
    return { userId: session.user_id, sessionId: session.id, role: session.role, status: session.status,
      actor: { kind: session.role === 'user' ? 'user' : 'admin', id: session.user_id, userId: session.user_id, role: session.role, requestId, ipHash: this.signal(`ip:${ip}`) } };
  }
  async currentUser(userId: string) { const row = (await this.db.query('SELECT * FROM users WHERE id=$1', [userId])).rows[0]; ensure(row, 'not_found', 404); return userDto(row); }
  async logout(principal: Principal) {
    await this.db.transaction(async tx => {
      await tx.query('UPDATE user_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE id=$1 AND user_id=$2', [principal.sessionId,principal.userId]);
      await audit(tx, principal.actor, principal.userId, 'auth.logout', 'session', principal.sessionId, 'Session token digest revoked; replay cannot reopen it.');
    });
    return { signedOut: true };
  }
}
