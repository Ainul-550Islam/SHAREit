# Part 6 — File 26–30

## Part 6B — File 28–30 + complete integration

## File 28 — `lib/screens/offerwall_screen.dart` — NEW

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import '../services/offerwall_service.dart';
import '../services/share_coin_service.dart';

class OfferwallScreen extends StatefulWidget {
  const OfferwallScreen({
    super.key,
    required this.service,
    this.controller,
    this.policy,
    this.launcher = launchRewardLink,
    this.onCatalogInfo,
  });
  final ShareCoinService service;
  final OfferwallController? controller;
  final OfferResourcePolicy? policy;
  final RewardLinkLauncher launcher;
  final VoidCallback? onCatalogInfo;
  @override
  State<OfferwallScreen> createState() => _OfferwallScreenState();
}

class _OfferwallScreenState extends State<OfferwallScreen>
    with WidgetsBindingObserver {
  late final OfferwallController _controller;
  late final bool _owns;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  String? _inputError;
  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _controller =
        widget.controller ??
        OfferwallController(
          service: widget.service,
          policy: widget.policy,
          launcher: widget.launcher,
          platform: Platform.isIOS ? OfferPlatform.ios : OfferPlatform.android,
        );
    _search.text = _controller.value.filter.search;
    _scroll.addListener(_nearEnd);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.refresh());
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 350 &&
        _controller.value.state == OfferLoadState.ready &&
        !_controller.value.windowFull) {
      unawaited(_controller.loadMore());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _controller.suspend();
    } else if (state == AppLifecycleState.resumed) {
      _controller.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_nearEnd);
    _scroll.dispose();
    _search.dispose();
    if (_owns) _controller.dispose();
    super.dispose();
  }

  void _filter({
    String? search,
    OfferCategory? category,
    bool changeCategory = false,
    OfferSort? sort,
    int? minimum,
    int? maximum,
    bool changeReward = false,
  }) {
    final old = _controller.value.filter;
    try {
      final value = OfferwallFilter(
        search: search ?? old.search,
        category: changeCategory ? category : old.category,
        sort: sort ?? old.sort,
        platform: old.platform,
        country: old.country,
        minimumReward: changeReward ? minimum : old.minimumReward,
        maximumReward: changeReward ? maximum : old.maximumReward,
      );
      setState(() => _inputError = null);
      _controller.setFilter(value, delayed: search != null);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (_) {
      setState(
        () => _inputError = 'Use valid whole-coin bounds and a search of at most 120 UTF-8 bytes.',
      );
    }
  }

  Future<void> _rewardFilter() async {
    final minimum = TextEditingController(
      text: _controller.value.filter.minimumReward?.toString() ?? '',
    );
    final maximum = TextEditingController(
      text: _controller.value.filter.maximumReward?.toString() ?? '',
    );
    String? error;
    final result = await showDialog<(int?, int?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Reward range'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  key: const ValueKey('offer-min-reward'),
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum ShareCoin (optional)',
                  ),
                ),
                TextField(
                  key: const ValueKey('offer-max-reward'),
                  controller: maximum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum ShareCoin (optional)',
                  ),
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('apply-offer-reward-filter'),
              onPressed: () {
                try {
                  final low = minimum.text.trim().isEmpty
                      ? null
                      : coinInt(int.tryParse(minimum.text), 'minimumReward');
                  final high = maximum.text.trim().isEmpty
                      ? null
                      : coinInt(int.tryParse(maximum.text), 'maximumReward');
                  OfferwallFilter(minimumReward: low, maximumReward: high);
                  Navigator.pop(dialogContext, (low, high));
                } catch (_) {
                  update(
                    () => error = 'Enter nonnegative whole numbers, minimum not above maximum.',
                  );
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    minimum.dispose();
    maximum.dispose();
    if (mounted && result != null) {
      _filter(minimum: result.$1, maximum: result.$2, changeReward: true);
    }
  }

  Future<void> _detail(Offer offer) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) =>
          OfferDetailScreen(controller: _controller, offer: offer),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('offerwall-screen'),
      appBar: AppBar(
        title: const Text('Offers'),
        toolbarHeight: 70,
        actions: <Widget>[
          if (widget.onCatalogInfo != null)
            IconButton(
              tooltip: 'Catalog information',
              onPressed: widget.onCatalogInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          IconButton(
            key: const ValueKey('refresh-offerwall'),
            tooltip: 'Refresh offers',
            onPressed: _controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ValueListenableBuilder<OfferwallState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                final featured = state.items
                    .where((offer) => offer.featured)
                    .take(5)
                    .toList();
                return RefreshIndicator(
                  onRefresh: _controller.refresh,
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF164D3C),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Text(
                                      'SHAREBONDHU · OFFERWALL',
                                      style: TextStyle(
                                        color: Color(0xFFD5F391),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Earn ShareCoin',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Explore tasks. Read the terms. Rewards require provider and backend verification.',
                                      style: TextStyle(
                                        color: Color(0xFFE0EDE5),
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                key: const ValueKey('offer-search'),
                                controller: _search,
                                maxLength: 120,
                                onChanged: (text) => _filter(search: text),
                                decoration: InputDecoration(
                                  hintText: 'Search offers or publishers',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  errorText: _inputError,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        key: const ValueKey(
                                          'offer-category-all',
                                        ),
                                        label: const Text('All'),
                                        selected: state.filter.category == null,
                                        onSelected: (_) =>
                                            _filter(changeCategory: true),
                                      ),
                                    ),
                                    for (final category in OfferCategory.values)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          key: ValueKey(
                                            'offer-category-${category.name}',
                                          ),
                                          label: Text(
                                            offerCategoryLabel(category),
                                          ),
                                          selected:
                                              state.filter.category == category,
                                          onSelected: (_) => _filter(
                                            category: category,
                                            changeCategory: true,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  OutlinedButton.icon(
                                    key: const ValueKey('offer-reward-filter'),
                                    onPressed: _rewardFilter,
                                    icon: const Icon(Icons.tune_rounded),
                                    label: const Text('Reward filter'),
                                  ),
                                  SizedBox(
                                    width: 260,
                                    child: DropdownButton<OfferSort>(
                                      isExpanded: true,
                                      key: const ValueKey('offer-sort'),
                                      value: state.filter.sort,
                                      underline: const SizedBox.shrink(),
                                      items:
                                          const <DropdownMenuItem<OfferSort>>[
                                            DropdownMenuItem(
                                              value: OfferSort.recommended,
                                              child: Text(
                                                'Recommended',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: OfferSort.rewardHigh,
                                              child: Text(
                                                'Highest reward',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: OfferSort.rewardLow,
                                              child: Text(
                                                'Lowest reward',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: OfferSort.timeShort,
                                              child: Text(
                                                'Shortest time',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                      onChanged: (sort) {
                                        if (sort != null) _filter(sort: sort);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              if (state.filter.minimumReward != null ||
                                  state.filter.maximumReward != null)
                                Text(
                                  'Range: ${state.filter.minimumReward ?? 0} – ${state.filter.maximumReward?.toString() ?? 'no upper filter'} ShareCoin',
                                ),
                              if (state.cached || state.stale)
                                const _OfferNotice(
                                  'Cached or stale catalog. Go online and refresh before starting or confirming rewards.',
                                ),
                              if (state.message != null)
                                _OfferNotice(state.message!),
                              if (_controller.actionMessage != null)
                                _OfferNotice(_controller.actionMessage!),
                              if (featured.isNotEmpty &&
                                  state.filter.category == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Text(
                                    'Featured offers',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (featured.isNotEmpty &&
                                  state.filter.category == null)
                                SizedBox(
                                  height:
                                      70 +
                                      MediaQuery.textScalerOf(context)
                                              .scale(14) *
                                          5,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: featured.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, index) {
                                      final offer = featured[index];
                                      return SizedBox(
                                        width: 220,
                                        child: Card(
                                          child: InkWell(
                                            onTap: () => _detail(offer),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Text(
                                                    offer.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Up to ${offer.rewardCoins} ShareCoin',
                                                    maxLines: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Text(
                                '${state.items.length} loaded · ${state.total} reported offers',
                                key: const ValueKey('offer-count'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (state.items.isEmpty && state.busy)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => Container(
                                height: 115,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              childCount: 3,
                            ),
                          ),
                        ),
                      if (state.items.isEmpty && !state.busy)
                        SliverPadding(
                          padding: const EdgeInsets.all(20),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              children: <Widget>[
                                Icon(
                                  state.state == OfferLoadState.error
                                      ? Icons.cloud_off_rounded
                                      : Icons.search_off_rounded,
                                  size: 46,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  state.state == OfferLoadState.error
                                      ? 'Offers unavailable'
                                      : 'No matching offers',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Availability is set by the backend for your account and region. No sample production offers are inserted.',
                                ),
                                TextButton(
                                  onPressed: _controller.refresh,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final offer = _controller.currentOffer(
                              state.items[index],
                            );
                            return _OfferCard(
                              offer: offer,
                              controller: _controller,
                              onOpen: () => _detail(offer),
                            );
                          }, childCount: state.items.length),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: <Widget>[
                              if (state.busy) const LinearProgressIndicator(),
                              if (!state.busy && state.hasNext)
                                OutlinedButton(
                                  key: const ValueKey('offer-load-more'),
                                  onPressed: state.windowFull
                                      ? () async {
                                          await _controller.nextWindow();
                                          if (mounted && _scroll.hasClients) {
                                            _scroll.jumpTo(0);
                                          }
                                        }
                                      : _controller.loadMore,
                                  child: Text(
                                    state.windowFull
                                        ? 'Next offer window'
                                        : state.state == OfferLoadState.error
                                        ? 'Retry next page'
                                        : 'Load more offers',
                                  ),
                                ),
                              if (!state.busy &&
                                  state.page != null &&
                                  !state.hasNext)
                                const Text(
                                  'End of available offers',
                                  key: ValueKey('offer-end'),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                'At most ${_controller.windowSize} offers are kept in this screen window. More can be browsed in subsequent windows. Country availability and rewards are not guaranteed.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.controller,
    required this.onOpen,
  });
  final Offer offer;
  final OfferwallController controller;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = controller.statusOf(offer);
    return Container(
      key: ValueKey('offer-card-${offer.offerId}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              OfferThumbnail(cache: controller.images, uri: offer.iconUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      offer.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(offer.publisher),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            offer.shortDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: <Widget>[
              Text(
                '${offer.rewardCoins} ShareCoin potential',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text('${offer.estimatedMinutes} min estimate'),
              Text(offerCategoryLabel(offer.category)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            controller.statusLabel(offer),
            key: ValueKey('offer-status-${offer.offerId}'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              key: ValueKey('open-offer-${offer.offerId}'),
              onPressed: onOpen,
              child: Text(
                status == OfferStatus.available
                    ? 'Start Offer'
                    : status == OfferStatus.started
                    ? 'In Progress'
                    : 'View / check status',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OfferThumbnail extends StatefulWidget {
  const OfferThumbnail({
    super.key,
    required this.cache,
    required this.uri,
    this.size = 54,
  });
  final OfferThumbnailCache cache;
  final Uri? uri;
  final double size;
  @override
  State<OfferThumbnail> createState() => _OfferThumbnailState();
}

class _OfferThumbnailState extends State<OfferThumbnail> {
  Uint8List? _bytes;
  MemoryImage? _image;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OfferThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.cache != widget.cache) _load();
  }

  void _load() {
    final generation = ++_generation;
    final previous = _image;
    _bytes = null;
    _image = null;
    _loading = true;
    if (previous != null) unawaited(previous.evict());
    widget.cache
        .get(widget.uri)
        .then(
          (bytes) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _bytes = bytes;
              _image = bytes == null ? null : MemoryImage(bytes);
              _loading = false;
            });
          },
          onError: (Object error, StackTrace stack) {
            if (mounted && generation == _generation) {
              setState(() => _loading = false);
            }
          },
        );
  }

  @override
  void dispose() {
    _generation += 1;
    final image = _image;
    if (image != null) unawaited(image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: _image != null && _bytes != null
            ? Image(
                image: _image!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const Icon(Icons.broken_image_outlined),
              )
            : Icon(
                _loading ? Icons.image_outlined : Icons.apps_rounded,
                semanticLabel: _loading
                    ? 'Loading offer image'
                    : 'Offer image unavailable',
              ),
      ),
    ),
  );
}

class OfferDetailScreen extends StatefulWidget {
  const OfferDetailScreen({
    super.key,
    required this.controller,
    required this.offer,
  });
  final OfferwallController controller;
  final Offer offer;
  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  bool _accepted = false;
  bool _checking = false;
  late final String? _accountKey;
  @override
  void initState() {
    super.initState();
    _accountKey = widget.controller.service.accountKey;
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    await widget.controller.refreshOffer(widget.offer.offerId);
    if (mounted) setState(() => _checking = false);
  }

  Future<bool> _consent(Uri uri) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open provider destination?'),
            content: Text(
              'Continue to ${uri.host}? The provider may need tracking/attribution for eligibility. Opening, installing or registering alone does not guarantee a reward.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                key: const ValueKey('confirm-provider-link'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('offer-detail-screen'),
    appBar: AppBar(title: const Text('Offer details'), toolbarHeight: 70),
    body: SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) {
          if (_accountKey != widget.controller.service.accountKey) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Account changed. Return to the offer list and refresh.',
                ),
              ),
            );
          }
          final offer = widget.controller.currentOffer(widget.offer);
          final status = widget.controller.statusOf(offer);
          final theme = Theme.of(context);
          final terminal = <OfferStatus>{
            OfferStatus.expired,
            OfferStatus.rejected,
            OfferStatus.unavailable,
            OfferStatus.completed,
          }.contains(status);
          final active = widget.controller.isStarting(offer.offerId);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OfferThumbnail(
                    cache: widget.controller.images,
                    uri: offer.iconUrl,
                    size: 68,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          offer.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(offer.publisher),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '${offer.rewardCoins} ShareCoin potential · ${offer.estimatedMinutes} min estimate',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(widget.controller.statusLabel(offer)),
              const SizedBox(height: 18),
              Text(offer.description),
              const SizedBox(height: 18),
              Text('Requirements', style: theme.textTheme.titleLarge),
              for (final instruction in offer.instructions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('• $instruction'),
                ),
              const SizedBox(height: 18),
              Text('Terms', style: theme.textTheme.titleLarge),
              for (final term in offer.terms)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('• $term'),
                ),
              const SizedBox(height: 18),
              Text(
                'Platforms: ${offer.platforms.map((p) => p.name).join(', ')}',
              ),
              Text(
                'Country availability: ${offer.countries.isEmpty ? 'None returned' : offer.countries.join(', ')}',
              ),
              Text('Expires: ${offer.expiresAt.toLocal()}'),
              Text('Provider: ${offer.provider}'),
              const SizedBox(height: 14),
              const Text(
                'The backend decides account/country eligibility. A provider start is not a completed reward. Current credit requires a verified backend transaction.',
              ),
              CheckboxListTile(
                key: const ValueKey('offer-tracking-consent'),
                contentPadding: EdgeInsets.zero,
                value: _accepted,
                onChanged: active
                    ? null
                    : (value) => setState(() => _accepted = value ?? false),
                title: const Text(
                  'I understand the tracking requirements and that rewards are not guaranteed.',
                ),
              ),
              if (widget.controller.actionMessage != null)
                _OfferNotice(widget.controller.actionMessage!),
              FilledButton(
                key: const ValueKey('start-detailed-offer'),
                onPressed: !_accepted || terminal || active || _checking
                    ? null
                    : () => widget.controller.start(offer, consent: _consent),
                child: Text(
                  active
                      ? 'Starting offer'
                      : status == OfferStatus.started ||
                            status == OfferStatus.pending
                      ? 'Open offer'
                      : 'Start Offer',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('check-offer-status'),
                onPressed: active || _checking ? null : _check,
                child: Text(
                  _checking
                      ? 'Checking backend'
                      : 'Refresh status / verify reward',
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _OfferNotice extends StatelessWidget {
  const _OfferNotice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12, bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(message),
  );
}
```

## File 29 — `lib/screens/reward_center_screen.dart` — NEW

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/offerwall_models.dart';
import '../models/share_coin_models.dart';
import '../services/offerwall_service.dart';
import '../services/share_coin_service.dart';
import 'offerwall_screen.dart' show OfferThumbnail;

abstract interface class RewardedAdAdapter {
  bool get configured;
  String? get provider;
  Stream<RewardedAdEvent> get events;
  Future<void> load(RewardSession session, AdConfiguration configuration);
  Future<void> show(String sessionId);
  Future<void> dismiss();
  Future<void> dispose();
}

class UnavailableRewardedAdAdapter implements RewardedAdAdapter {
  const UnavailableRewardedAdAdapter();
  @override
  bool get configured => false;
  @override
  String? get provider => null;
  @override
  Stream<RewardedAdEvent> get events => const Stream<RewardedAdEvent>.empty();
  @override
  Future<void> load(RewardSession session, AdConfiguration configuration) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> show(String sessionId) =>
      Future.error(const ShareCoinException(CoinErrorCode.notConfigured));
  @override
  Future<void> dismiss() async {}
  @override
  Future<void> dispose() async {}
}

RewardedAdAdapter createUnavailableRewardedAdAdapter() =>
    const UnavailableRewardedAdAdapter();

class RewardCoordinator extends ValueNotifier<RewardViewState> {
  RewardCoordinator({
    required this.service,
    RewardedAdAdapter? ad,
    OfferResourcePolicy? policy,
    this.launcher = launchRewardLink,
    this.adPlacement = 'rewarded',
    this.clock,
    this.autoTick = true,
  }) : ad = ad ?? createUnavailableRewardedAdAdapter(),
       policy = policy ?? OfferResourcePolicy(),
       super(const RewardViewState()) {
    coinId(adPlacement, 'adPlacement');
    _scope = service.accountKey;
    service.addListener(_accountChanged);
    _events = this.ad.events.listen(
      _onAdEvent,
      onError: (Object error, StackTrace stack) {
        if (!_closed &&
            !_submitted &&
            <RewardPhase>{
              RewardPhase.loading,
              RewardPhase.ready,
              RewardPhase.showing,
            }.contains(value.phase)) {
          _providerFailed = true;
          _emit(
            RewardPhase.failed,
            'The ad provider reported an error. No credit is inferred.',
          );
        }
      },
    );
  }
  final ShareCoinService service;
  final RewardedAdAdapter ad;
  final OfferResourcePolicy policy;
  final RewardLinkLauncher launcher;
  final String adPlacement;
  final Duration Function()? clock;
  final bool autoTick;
  final Stopwatch _watch = Stopwatch()..start();
  late final StreamSubscription<RewardedAdEvent> _events;
  Timer? _ticker;
  String? _scope, _requestKey;
  CoinData<RewardSession>? _session;
  DateTime? _anchor, _cooldownUntil;
  Duration _anchorTick = Duration.zero, _lastTick = Duration.zero;
  int _generation = 0;
  bool _closed = false,
      _suspended = false,
      _working = false,
      _submitted = false,
      _providerFailed = false;
  bool get canCheckStatus =>
      !_closed &&
      !_suspended &&
      !_working &&
      (_session != null || _requestKey != null);
  bool get canShow =>
      !_closed && !_suspended && !_working && value.phase == RewardPhase.ready;
  bool get hasUnresolved =>
      (_session != null || _requestKey != null) &&
      <RewardPhase>{
        RewardPhase.tracking,
        RewardPhase.rewardPending,
        RewardPhase.checkingCredit,
        RewardPhase.interrupted,
      }.contains(value.phase);
  Duration get _now {
    final next = clock?.call() ?? _watch.elapsed;
    if (next > _lastTick) _lastTick = next;
    return _lastTick;
  }

  DateTime? get serverEstimate => _anchor?.add(_now - _anchorTick);
  void _serverClock(DateTime time) {
    _anchor = time;
    _anchorTick = _now;
  }

  bool _valid(int generation, String? scope) =>
      !_closed &&
      !_suspended &&
      generation == _generation &&
      scope == service.accountKey;
  void _accountChanged() {
    if (_closed || _scope == service.accountKey) return;
    _scope = service.accountKey;
    _generation += 1;
    _session = null;
    _requestKey = null;
    _submitted = false;
    _working = false;
    _ticker?.cancel();
    _anchor = null;
    _cooldownUntil = null;
    unawaited(ad.dismiss().catchError((Object error) {}));
    value = const RewardViewState(
      message: 'Account changed. Start a new eligibility check.',
    );
  }

  void _emit(
    RewardPhase phase,
    String message, {
    RewardEvent? event,
    ShareCoinTransaction? transaction,
  }) {
    if (_closed) return;
    if (phase != RewardPhase.cooldown) {
      _ticker?.cancel();
      _ticker = null;
    }
    final now = serverEstimate;
    final remaining =
        now != null && _cooldownUntil != null && now.isBefore(_cooldownUntil!)
        ? _cooldownUntil!.difference(now)
        : Duration.zero;
    value = RewardViewState(
      phase: phase,
      session: _session?.data,
      event: event ?? value.event,
      transaction: transaction ?? value.transaction,
      message: message,
      cooldownRemaining: remaining,
    );
  }

  void refreshClock() {
    if (!_closed && !_suspended && value.phase == RewardPhase.cooldown) {
      _emit(
        value.phase,
        'Cooldown is a backend policy. Recheck eligibility when the timer ends.',
      );
    }
  }

  void _tickCooldown() {
    _ticker?.cancel();
    if (autoTick) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => refreshClock(),
      );
    }
  }

  bool _acceptSession(CoinData<RewardSession> response) {
    final session = response.data;
    if (session.issuedAt.isAfter(response.serverTime)) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    _session = response;
    _serverClock(response.serverTime);
    _cooldownUntil = session.notBefore;
    if (session.availability == RewardAvailability.dailyLimit) {
      _emit(
        RewardPhase.dailyLimit,
        'The backend daily limit has been reached. Device date does not reset it.',
      );
      return false;
    }
    if (session.availability == RewardAvailability.cooldown ||
        response.serverTime.isBefore(session.notBefore)) {
      _emit(
        RewardPhase.cooldown,
        'Wait for the backend cooldown, then recheck eligibility.',
      );
      _tickCooldown();
      return false;
    }
    if (!session.usableAt(response.serverTime)) {
      _emit(
        RewardPhase.failed,
        'This reward session is expired, restricted or unavailable.',
      );
      return false;
    }
    return true;
  }

  Future<void> loadAd() async {
    if (_closed ||
        _suspended ||
        _working ||
        value.busy ||
        hasUnresolved ||
        value.cooldownRemaining > Duration.zero) {
      return;
    }
    final generation = ++_generation;
    final scope = service.accountKey;
    _working = true;
    _submitted = false;
    _providerFailed = false;
    _session = null;
    _requestKey = null;
    _ticker?.cancel();
    _ticker = null;
    value = const RewardViewState(
      phase: RewardPhase.loading,
      message: 'Checking ad configuration and backend eligibility.',
    );
    try {
      if (!ad.configured || !service.rewardExtensionsAvailable) {
        throw const ShareCoinException(CoinErrorCode.notConfigured);
      }
      final configuration = await service.getAdConfiguration(
        allowCached: false,
      );
      if (!_valid(generation, scope)) return;
      if (configuration.data.premium ||
          !configuration.data.rewardedEnabled ||
          configuration.data.provider != ad.provider) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      _requestKey = newCoinRequestId();
      final response = await service.prepareRewardSession(
        CoinSource.adReward,
        adPlacement,
        idempotencyKey: _requestKey!,
      );
      if (!_valid(generation, scope)) return;
      if (response.data.provider != ad.provider ||
          response.data.dailyLimit > configuration.data.dailyLimit) {
        throw const ShareCoinException(CoinErrorCode.malformed);
      }
      if (!_acceptSession(response)) return;
      await ad
          .load(response.data, configuration.data)
          .timeout(const Duration(seconds: 30));
      if (!_valid(generation, scope)) {
        await ad.dismiss();
        return;
      }
      if (_providerFailed) {
        throw const ShareCoinException(CoinErrorCode.unavailable);
      }
      if (!response.data.usableAt(serverEstimate!)) {
        _emit(
          RewardPhase.failed,
          'Ad session expired before it was ready. Recheck eligibility.',
        );
        return;
      }
      _emit(
        RewardPhase.ready,
        'Ad ready. Watching is not credit; the backend still verifies the provider event.',
      );
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(
          error is ShareCoinException && error.outcomeUncertain
              ? RewardPhase.interrupted
              : RewardPhase.failed,
          _message(error),
        );
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> showAd() async {
    final ticket = _session?.data;
    if (!canShow || ticket == null) return;
    if (serverEstimate == null || !ticket.usableAt(serverEstimate!)) {
      _emit(RewardPhase.failed, 'Ad session expired. Recheck eligibility.');
      return;
    }
    final generation = _generation;
    final scope = service.accountKey;
    _emit(
      RewardPhase.showing,
      'Showing provider ad. No ShareCoin has been awarded by the client.',
    );
    try {
      await ad.show(ticket.sessionId);
    } catch (error) {
      if (_valid(generation, scope)) _emit(RewardPhase.failed, _message(error));
    }
  }

  void _onAdEvent(RewardedAdEvent event) {
    final ticket = _session?.data;
    if (_closed ||
        _suspended ||
        ticket == null ||
        event.sessionId != ticket.sessionId ||
        service.accountKey != _scope) {
      return;
    }
    if (event.type == RewardedAdEventType.failed &&
        value.phase == RewardPhase.loading) {
      _providerFailed = true;
      _emit(RewardPhase.failed, 'Ad loading failed. No reward was submitted.');
      return;
    }
    if (event.type == RewardedAdEventType.ready ||
        event.type == RewardedAdEventType.shown) {
      return;
    }
    if (value.phase != RewardPhase.showing || _submitted) return;
    switch (event.type) {
      case RewardedAdEventType.completed:
        if (event.providerEventId == null ||
            serverEstimate == null ||
            !ticket.usableAt(serverEstimate!)) {
          _emit(
            RewardPhase.interrupted,
            'Provider evidence is missing or the session expired. Check backend status.',
          );
        } else {
          unawaited(_claim(event.providerEventId!));
        }
      case RewardedAdEventType.skipped:
        _emit(
          RewardPhase.skipped,
          'Ad skipped. No reward event was submitted.',
        );
      case RewardedAdEventType.failed:
        _emit(RewardPhase.failed, 'Ad failed. No reward event was submitted.');
      case RewardedAdEventType.ready:
      case RewardedAdEventType.shown:
        break;
    }
  }

  Future<void> _claim(String providerEventId) async {
    final ticket = _session?.data;
    if (_closed || _suspended || _submitted || ticket == null) return;
    _submitted = true;
    _working = true;
    final generation = _generation;
    final scope = service.accountKey;
    _emit(
      RewardPhase.completed,
      'Action completed. Submitting a claim, not adding local coins.',
    );
    try {
      final event = RewardEvent(
        eventId: ticket.eventId,
        userId: ticket.userId,
        source: ticket.source,
        provider: ticket.provider,
        providerEventId: providerEventId,
        targetId: ticket.targetId,
        requestedCoins: ticket.rewardCoins,
        occurredAt: serverEstimate ?? ticket.issuedAt,
        status: RewardEventStatus.created,
        idempotencyKey: ticket.idempotencyKey,
        metadata: {'trace': ticket.sessionId},
      );
      final result = await service.submitRewardEvent(event);
      if (!_valid(generation, scope)) return;
      await _eventResult(result.data, generation, scope);
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(
          error is ShareCoinException &&
                  error.code == CoinErrorCode.invalidRequest
              ? RewardPhase.rejected
              : RewardPhase.interrupted,
          _message(error),
        );
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> _eventResult(
    RewardEvent event,
    int generation,
    String? scope,
  ) async {
    final ticket = _session!.data;
    if (event.eventId != ticket.eventId ||
        event.userId != ticket.userId ||
        event.source != ticket.source ||
        event.provider != ticket.provider ||
        event.targetId != ticket.targetId ||
        event.idempotencyKey != ticket.idempotencyKey ||
        event.requestedCoins != ticket.rewardCoins) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    if (event.status == RewardEventStatus.rejected ||
        event.status == RewardEventStatus.cancelled) {
      _emit(
        RewardPhase.rejected,
        'Backend rejected or cancelled this reward.',
        event: event,
      );
      return;
    }
    if (event.status != RewardEventStatus.approved ||
        event.transactionId == null) {
      _emit(
        RewardPhase.rewardPending,
        'Reward Pending — waiting for backend validation.',
        event: event,
      );
      return;
    }
    _emit(
      RewardPhase.checkingCredit,
      'Approval reported. Verifying the ledger transaction.',
      event: event,
    );
    final response = await service.getTransaction(event.transactionId!);
    if (!_valid(generation, scope)) return;
    final transaction = response.data;
    if (transaction.source != ticket.source ||
        transaction.referenceId != ticket.targetId ||
        transaction.direction != CoinDirection.credit) {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    if (transaction.status == CoinTransactionStatus.reversed) {
      _emit(
        RewardPhase.reversed,
        'This reward was reversed by the backend.',
        event: event,
        transaction: transaction,
      );
      return;
    }
    if (transaction.status == CoinTransactionStatus.rejected ||
        transaction.status == CoinTransactionStatus.cancelled) {
      _emit(
        RewardPhase.rejected,
        'The ledger did not post this reward.',
        event: event,
        transaction: transaction,
      );
      return;
    }
    if (transaction.status != CoinTransactionStatus.completed) {
      _emit(
        RewardPhase.rewardPending,
        'The ledger transaction is still pending.',
        event: event,
      );
      return;
    }
    _emit(
      RewardPhase.rewardApproved,
      'Backend confirmed ${transaction.signedAmount}.',
      event: event,
      transaction: transaction,
    );
    try {
      await service.getCurrentWallet(allowCached: false);
    } catch (_) {
      if (_valid(generation, scope)) {
        _emit(
          RewardPhase.rewardApproved,
          'Credit confirmed; refresh the wallet when the service is available.',
          event: event,
          transaction: transaction,
        );
      }
    }
  }

  Future<void> claimDaily() async {
    if (_closed ||
        _suspended ||
        _working ||
        value.busy ||
        hasUnresolved ||
        value.cooldownRemaining > Duration.zero) {
      return;
    }
    final generation = ++_generation;
    final scope = service.accountKey;
    _working = true;
    _submitted = false;
    _providerFailed = false;
    _session = null;
    _requestKey = null;
    _ticker?.cancel();
    _ticker = null;
    value = const RewardViewState(
      phase: RewardPhase.loading,
      message: 'Checking the backend daily reward policy.',
    );
    try {
      final config = await service.getDailyRewardConfiguration(
        allowCached: false,
      );
      if (!_valid(generation, scope)) return;
      _serverClock(config.serverTime);
      _cooldownUntil = config.data.nextEligibleAt;
      if (!config.data.eligible) {
        _emit(
          RewardPhase.cooldown,
          'The backend has not made the daily reward available.',
        );
        _tickCooldown();
        return;
      }
      _requestKey = newCoinRequestId();
      final response = await service.prepareRewardSession(
        CoinSource.dailyReward,
        config.data.version,
        idempotencyKey: _requestKey!,
      );
      if (!_valid(generation, scope)) return;
      if (response.data.rewardCoins !=
          config.data.dayRewards[config.data.streakDay - 1]) {
        throw const ShareCoinException(CoinErrorCode.policyChanged);
      }
      if (!_acceptSession(response)) return;
      await _claim(response.data.providerEventId!);
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(RewardPhase.interrupted, _message(error));
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> startPromotion(
    Promotion promotion, {
    Future<bool> Function(Uri)? consent,
  }) async {
    if (_closed || _suspended || _working || value.busy || hasUnresolved) {
      return;
    }
    final generation = ++_generation;
    final scope = service.accountKey;
    _working = true;
    _submitted = false;
    _providerFailed = false;
    _session = null;
    _requestKey = null;
    _ticker?.cancel();
    _ticker = null;
    value = const RewardViewState(
      phase: RewardPhase.loading,
      message: 'Creating a backend tracking session. A click is not a reward.',
    );
    try {
      if (policy.linkOrigins.isEmpty) {
        throw const ShareCoinException(CoinErrorCode.notConfigured);
      }
      _requestKey = newCoinRequestId();
      final response = await service.prepareRewardSession(
        CoinSource.promotionReward,
        promotion.campaignId,
        idempotencyKey: _requestKey!,
      );
      if (!_valid(generation, scope)) return;
      if (!promotion.availableAt(response.serverTime) ||
          !_acceptSession(response)) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      final url = response.data.launchUrl;
      if (!policy.allowsLink(url)) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      if (consent != null && !await consent(url!)) {
        if (_valid(generation, scope)) {
          _emit(
            RewardPhase.tracking,
            'Tracking session created, but the link was not opened. No reward is inferred.',
          );
        }
        return;
      }
      if (!_valid(generation, scope)) return;
      final opened = await launcher(url!);
      if (_valid(generation, scope)) {
        _emit(
          RewardPhase.tracking,
          opened
              ? 'Campaign opened. Waiting for provider verification; no click credit.'
              : 'The provider link could not open. Check backend tracking status before starting again.',
        );
      }
    } catch (error) {
      if (_valid(generation, scope)) _emit(RewardPhase.failed, _message(error));
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshStatus() async {
    if (_closed ||
        _suspended ||
        _working ||
        _session == null && _requestKey == null) {
      return;
    }
    final generation = _generation;
    final scope = service.accountKey;
    _working = true;
    try {
      if (_session == null) {
        final result = await service.getRewardSessionStatus(
          requestKey: _requestKey,
        );
        if (!_valid(generation, scope)) return;
        _session = result;
        _serverClock(result.serverTime);
        if (result.data.availability != RewardAvailability.eligible &&
            !_acceptSession(result)) {
          return;
        }
      }
      final event = await service.getRewardEventStatus(_session!.data.eventId);
      if (_valid(generation, scope)) {
        await _eventResult(event.data, generation, scope);
      }
    } catch (error) {
      if (_valid(generation, scope)) {
        _emit(
          error is ShareCoinException && error.code == CoinErrorCode.notFound
              ? RewardPhase.tracking
              : RewardPhase.interrupted,
          error is ShareCoinException && error.code == CoinErrorCode.notFound
              ? 'No verified provider event is available yet. Check later; do not create a duplicate claim.'
              : _message(error),
        );
      }
    } finally {
      if (!_closed && generation == _generation) {
        _working = false;
        notifyListeners();
      }
    }
  }

  String _message(Object error) => error is ShareCoinException
      ? error.message
      : 'The reward action could not be confirmed. Check backend history.';
  void suspend() {
    if (_closed) return;
    _suspended = true;
    _generation += 1;
    _working = false;
    _ticker?.cancel();
    unawaited(ad.dismiss().catchError((Object error) {}));
    if (_session != null &&
        !value.credited &&
        value.phase != RewardPhase.rejected &&
        value.phase != RewardPhase.reversed) {
      _emit(
        RewardPhase.interrupted,
        'Action interrupted. Provider/server status, not local state, decides any reward.',
      );
    }
  }

  void resume() {
    if (_closed) return;
    _suspended = false;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    _ticker?.cancel();
    _watch.stop();
    service.removeListener(_accountChanged);
    unawaited(_events.cancel());
    unawaited(ad.dispose().catchError((Object error) {}));
    super.dispose();
  }
}

enum RewardCenterMode { ad, daily, promotions, transactions, withdrawals }

class RewardCenterScreen extends StatefulWidget {
  const RewardCenterScreen({
    super.key,
    required this.service,
    required this.mode,
    this.policy,
    this.adFactory = createUnavailableRewardedAdAdapter,
    this.launcher = launchRewardLink,
    this.onConfiguration,
  });
  final ShareCoinService service;
  final RewardCenterMode mode;
  final OfferResourcePolicy? policy;
  final RewardedAdAdapter Function() adFactory;
  final RewardLinkLauncher launcher;
  final VoidCallback? onConfiguration;
  @override
  State<RewardCenterScreen> createState() => _RewardCenterScreenState();
}

class _RewardCenterScreenState extends State<RewardCenterScreen>
    with WidgetsBindingObserver {
  late final RewardCoordinator _rewards;
  late final OfferThumbnailCache _images;
  CoinFeedController<Promotion>? _promotions;
  CoinFeedController<ShareCoinTransaction>? _transactions;
  CoinFeedController<WithdrawalRequest>? _withdrawals;
  CoinData<DailyRewardConfiguration>? _daily;
  String? _error;
  int _generation = 0;
  String? _scope;
  String get _title => switch (widget.mode) {
    RewardCenterMode.ad => 'Rewarded Ads',
    RewardCenterMode.daily => 'Daily Reward',
    RewardCenterMode.promotions => 'Promotions',
    RewardCenterMode.transactions => 'Transactions',
    RewardCenterMode.withdrawals => 'Withdrawal History',
  };
  @override
  void initState() {
    super.initState();
    _rewards = RewardCoordinator(
      service: widget.service,
      ad: widget.adFactory(),
      policy: widget.policy,
      launcher: widget.launcher,
    );
    _images = OfferThumbnailCache(
      policy: _rewards.policy,
      canFetch: () => widget.service.connectivity.value.canRequestRewards,
    );
    if (widget.mode == RewardCenterMode.promotions) {
      _promotions = CoinFeedController(
        service: widget.service,
        fetch: (query) => widget.service.getPromotions(query: query),
        id: (item) => item.campaignId,
      );
    }
    if (widget.mode == RewardCenterMode.transactions) {
      _transactions = CoinFeedController(
        service: widget.service,
        fetch: (query) => widget.service.getTransactionHistory(query: query),
        id: (item) => item.transactionId,
      );
    }
    if (widget.mode == RewardCenterMode.withdrawals) {
      _withdrawals = CoinFeedController(
        service: widget.service,
        fetch: (query) => widget.service.getWithdrawalHistory(query: query),
        id: (item) => item.withdrawalId,
      );
    }
    _scope = widget.service.accountKey;
    widget.service.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _accountChanged() {
    if (!mounted || _scope == widget.service.accountKey) return;
    _scope = widget.service.accountKey;
    _generation += 1;
    _images.clear();
    setState(() {
      _daily = null;
      _error = 'Account changed. Refresh this view.';
    });
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      if (_promotions != null) await _promotions!.refresh();
      if (_transactions != null) await _transactions!.refresh();
      if (_withdrawals != null) await _withdrawals!.refresh();
      if (widget.mode == RewardCenterMode.daily) {
        final data = await widget.service.getDailyRewardConfiguration();
        if (mounted && generation == _generation) {
          setState(() {
            _daily = data;
            _error = null;
          });
        }
      }
      if (widget.mode == RewardCenterMode.ad) {
        await widget.service.getServiceStatus();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is ShareCoinException
              ? error.message
              : 'Could not load this reward view.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generation += 1;
      _rewards.suspend();
      _promotions?.suspend();
      _transactions?.suspend();
      _withdrawals?.suspend();
    } else if (state == AppLifecycleState.resumed) {
      _rewards.resume();
      _promotions?.resume();
      _transactions?.resume();
      _withdrawals?.resume();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    widget.service.removeListener(_accountChanged);
    _rewards.dispose();
    _images.dispose();
    _promotions?.dispose();
    _transactions?.dispose();
    _withdrawals?.dispose();
    super.dispose();
  }

  Future<bool> _consent(Uri uri) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open campaign?'),
            content: Text(
              'Continue to ${uri.host}? Tracking may be required. Clicking does not guarantee payment.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open provider'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('reward-center-screen'),
    appBar: AppBar(
      title: Text(_title),
      toolbarHeight: 70,
      actions: <Widget>[
        if (widget.onConfiguration != null)
          IconButton(
            tooltip: 'Configuration and previous view',
            onPressed: widget.onConfiguration,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        IconButton(
          tooltip: 'Refresh backend data',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: _body(),
        ),
      ),
    ),
  );

  Widget _body() {
    if (_promotions != null) {
      return _feed(
        _promotions!,
        (promotion) => _promotionCard(promotion),
        header: _rewardPanel(),
      );
    }
    if (_transactions != null) {
      return _feed(
        _transactions!,
        (transaction) => Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.signedAmount,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '${transaction.source.name} · ${transaction.status.name}',
                  key: ValueKey(
                    'transaction-status-${transaction.transactionId}',
                  ),
                ),
                const SizedBox(height: 6),
                Text(transaction.description),
                Text(transaction.createdAt.toLocal().toString()),
                SelectableText(transaction.transactionId),
              ],
            ),
          ),
        ),
      );
    }
    if (_withdrawals != null) {
      return _feed(
        _withdrawals!,
        (request) => Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${request.requestedCoins} ShareCoin requested',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${request.method.name} · ${request.status.name}'),
                Text(request.maskedDestination),
                Text('Fee: ${request.rate.formatMinor(request.feeMinor)}'),
                Text(
                  'Final amount: ${request.rate.formatMinor(request.finalPayoutMinor)}',
                ),
                Text(request.updatedAt.toLocal().toString()),
                SelectableText(request.withdrawalId),
                if (request.rejectionReason != null)
                  Text(request.rejectionReason!),
                const Text(
                  'Status is reported by the backend, not a local payout action.',
                ),
              ],
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          _header(
            widget.mode == RewardCenterMode.ad
                ? 'Watch. Verify. Refresh.'
                : 'Your daily check-in.',
          ),
          if (_error != null) _RewardNotice(_error!),
          if (widget.mode == RewardCenterMode.ad)
            const _RewardNotice(
              'A compliant rewarded-ad provider adapter and authenticated reward backend are required. This build does not simulate ad playback or cash earnings.',
            ),
          if (_daily != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Backend streak: Day ${_daily!.data.streakDay}'),
                    if (_daily!.cached)
                      const Text(
                        'Cached policy — fresh eligibility is checked before claiming.',
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (
                          var i = 0;
                          i < _daily!.data.dayRewards.length;
                          i += 1
                        )
                          Chip(
                            label: Text(
                              'Day ${i + 1}: ${_daily!.data.dayRewards[i]}',
                            ),
                          ),
                      ],
                    ),
                    const Text(
                      'Reward values and eligibility come from the backend, never from device date.',
                    ),
                  ],
                ),
              ),
            ),
          _rewardPanel(),
        ],
      ),
    );
  }

  Widget _header(String title) => Container(
    padding: const EdgeInsets.all(24),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF164D3C),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'SHAREBONDHU · SHARECOIN',
          style: TextStyle(
            color: Color(0xFFD5F391),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Actions are not money. Only a validated backend ledger transaction confirms credit.',
          style: TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
        ),
      ],
    ),
  );

  Widget _rewardPanel() => ValueListenableBuilder<RewardViewState>(
    valueListenable: _rewards,
    builder: (context, state, child) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _phaseLabel(state.phase),
              key: const ValueKey('reward-phase'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(state.message, key: const ValueKey('reward-message')),
            if (state.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (state.session != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Backend usage before this session: ${state.session!.usedToday} / ${state.session!.dailyLimit}',
                ),
              ),
            if (state.cooldownRemaining > Duration.zero)
              Text('Cooldown: ${state.cooldownRemaining.inSeconds}s'),
            if (state.credited)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.transaction!.signedAmount,
                  key: const ValueKey('confirmed-reward-amount'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (widget.mode == RewardCenterMode.ad)
                  FilledButton(
                    key: const ValueKey('load-rewarded-ad'),
                    onPressed:
                        state.busy ||
                            _rewards.hasUnresolved ||
                            state.cooldownRemaining > Duration.zero
                        ? null
                        : _rewards.loadAd,
                    child: const Text('Load rewarded ad'),
                  ),
                if (widget.mode == RewardCenterMode.ad)
                  OutlinedButton(
                    key: const ValueKey('show-rewarded-ad'),
                    onPressed: _rewards.canShow ? _rewards.showAd : null,
                    child: const Text('Watch Ad'),
                  ),
                if (widget.mode == RewardCenterMode.daily)
                  FilledButton(
                    key: const ValueKey('claim-daily-reward'),
                    onPressed:
                        state.busy ||
                            _rewards.hasUnresolved ||
                            state.cooldownRemaining > Duration.zero
                        ? null
                        : _rewards.claimDaily,
                    child: const Text('Check and claim daily reward'),
                  ),
                OutlinedButton(
                  key: const ValueKey('refresh-reward-status'),
                  onPressed: _rewards.canCheckStatus
                      ? _rewards.refreshStatus
                      : null,
                  child: const Text('Check reward status'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _promotionCard(Promotion promotion) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              OfferThumbnail(cache: _images, uri: promotion.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  promotion.title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(promotion.advertiser),
          Text(promotion.description),
          Text(
            '${promotion.rewardCoins} ShareCoin potential · ${promotion.status.name}',
          ),
          Text('Ends ${promotion.endsAt.toLocal()}'),
          SelectableText(promotion.campaignId),
          const SizedBox(height: 12),
          ValueListenableBuilder<RewardViewState>(
            valueListenable: _rewards,
            builder: (context, state, child) => FilledButton(
              key: ValueKey('start-promotion-${promotion.campaignId}'),
              onPressed: state.busy || _rewards.hasUnresolved
                  ? null
                  : () => _rewards.startPromotion(promotion, consent: _consent),
              child: Text(promotion.cta),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _feed<T>(
    CoinFeedController<T> controller,
    Widget Function(T) row, {
    Widget? header,
  }) => ValueListenableBuilder<CoinFeedState<T>>(
    valueListenable: controller,
    builder: (context, state, child) => RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _header(_title),
                  ?header,
                  if (state.cached)
                    const _RewardNotice(
                      'Cached records. Refresh before treating status as current.',
                    ),
                  if (state.error != null) _RewardNotice(state.error!),
                  if (state.items.isEmpty && !state.loading)
                    const Text('No records available from the backend.'),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => row(state.items[index]),
                childCount: state.items.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: <Widget>[
                  if (state.loading) const LinearProgressIndicator(),
                  if (!state.loading && state.page?.hasNext == true)
                    OutlinedButton(
                      onPressed: controller.more,
                      child: Text(
                        state.windowFull ? 'Next record window' : 'Load more',
                      ),
                    ),
                  if (!state.loading && state.error != null)
                    TextButton(
                      onPressed: controller.refresh,
                      child: const Text('Retry'),
                    ),
                  if (!state.loading &&
                      state.page != null &&
                      !state.page!.hasNext)
                    const Text('End of records'),
                  const SizedBox(height: 12),
                  const Text(
                    'Rejected, cancelled and reversed entries are not hidden. This client does not create payout success or credit money locally.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _phaseLabel(RewardPhase phase) => switch (phase) {
    RewardPhase.idle => 'Ready for an action',
    RewardPhase.loading => 'Loading / checking eligibility',
    RewardPhase.ready => 'Ad ready',
    RewardPhase.showing => 'Ad showing',
    RewardPhase.completed => 'Provider completion received',
    RewardPhase.skipped => 'Ad skipped',
    RewardPhase.failed => 'Action unavailable',
    RewardPhase.tracking => 'Provider tracking',
    RewardPhase.rewardPending => 'Reward Pending',
    RewardPhase.checkingCredit => 'Checking ledger credit',
    RewardPhase.rewardApproved => 'Reward Approved',
    RewardPhase.cooldown => 'Cooldown',
    RewardPhase.dailyLimit => 'Daily limit reached',
    RewardPhase.rejected => 'Reward Rejected',
    RewardPhase.reversed => 'Reward Reversed',
    RewardPhase.interrupted => 'Confirmation required',
  };
}

class _RewardNotice extends StatelessWidget {
  const _RewardNotice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(message),
  );
}
```

## File 30 — `test/offerwall_rewards_test.dart` — NEW

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharebondhu/models/offerwall_models.dart';
import 'package:sharebondhu/models/share_file.dart';
import 'package:sharebondhu/models/share_coin_models.dart';
import 'package:sharebondhu/models/user_models.dart';
import 'package:sharebondhu/screens/home_screen.dart';
import 'package:sharebondhu/screens/offerwall_screen.dart';
import 'package:sharebondhu/screens/reward_center_screen.dart';
import 'package:sharebondhu/screens/share_coin_home_screen.dart';
import 'package:sharebondhu/services/connectivity_service.dart';
import 'package:sharebondhu/services/offerwall_service.dart';
import 'package:sharebondhu/services/share_coin_service.dart';

import 'transfer_progress_test.dart' as p5;
import 'widget_test.dart' as baseline;

final offerTestTime = DateTime.utc(2026, 9, 9, 12);

// Lightweight test catalog only. Production code never imports this fixture.
List<Offer> createOfferFixture([int count = 300]) => List<Offer>.generate(
  count,
  (index) => Offer(
    offerId: 'offer-${index.toString().padLeft(4, '0')}',
    title: 'Offer ${index.toString().padLeft(3, '0')}',
    shortDescription: 'A lightweight test task.',
    description: 'Fixture only; no real advertiser or payout.',
    publisher: 'Publisher ${index % 7}',
    category: OfferCategory.values[index % OfferCategory.values.length],
    rewardCoins: 100 + index,
    estimatedMinutes: 1 + index % 30,
    platforms: const [OfferPlatform.android, OfferPlatform.ios],
    countries: const ['BD'],
    status: OfferStatus.available,
    startsAt: offerTestTime.subtract(const Duration(days: 1)),
    expiresAt: offerTestTime.add(const Duration(days: 2)),
    provider: 'test-provider',
    featured: index % 40 == 0,
    sortPriority: index,
    iconUrl: Uri.parse('https://assets.example.org/$index.png'),
    instructions: const ['Complete the provider task.'],
    terms: const ['Backend validation required.'],
  ),
);

class OfferTestBackend extends p5.TestShareCoinBackend
    implements ShareCoinRewardBackend {
  OfferTestBackend([int count = 300]) : catalog = createOfferFixture(count);
  final List<Offer> catalog;
  final Map<String, OfferStart> starts = {};
  final Map<String, RewardSession> sessions = {};
  final Map<String, RewardEvent> rewardEvents = {};
  final Map<String, ShareCoinTransaction> ledger = {};
  final Map<ShareCoinRewardOperation, int> extensionCalls = {};
  final Map<String, String> offerTransactions = {};
  RewardAvailability availability = RewardAvailability.eligible;
  int used = 0, limit = 5;
  bool approveImmediately = false,
      rejectSignature = false,
      duplicatePage = false;
  Uri launch = Uri.parse('https://offers.example.org/task');
  OfferStatus? forcedOfferStatus;
  Future<Map<String, dynamic>> Function(
    ShareCoinRewardOperation,
    AccountScope,
    Map<String, Object?>,
  )?
  extensionHandler;

  @override
  Map<String, dynamic> envelope(
    AccountScope owner,
    Map<String, Object?> data,
  ) => {
    'userId': owner.userId,
    'serverTime': offerTestTime.toIso8601String(),
    'version': 'test-v6',
    'data': data,
  };

  Offer offer(String id) {
    final original = catalog.where((item) => item.offerId == id).firstOrNull;
    if (original == null) {
      throw const ShareCoinException(CoinErrorCode.notFound);
    }
    final json = original.toJson();
    if (offerTransactions.containsKey(id)) {
      json['status'] = OfferStatus.completed.name;
      json['rewardTransactionId'] = offerTransactions[id];
    } else if (forcedOfferStatus != null) {
      json['status'] = forcedOfferStatus!.name;
    } else if (starts.containsKey(id)) {
      json['status'] = starts[id]!.status.name;
    }
    return Offer.fromJson(json);
  }

  @override
  Map<String, Object?> dataFor(
    ShareCoinOperation op,
    AccountScope owner,
    Map<String, Object?> args,
  ) {
    if (op == ShareCoinOperation.offers) {
      final query = OfferQuery.fromJson(args);
      final filter = OfferwallFilter(
        search: query.search,
        category: query.category,
        sort: query.sort,
        platform: query.platform,
        country: query.country,
        minimumReward: args['minimumReward'] as int?,
        maximumReward: args['maximumReward'] as int?,
      );
      final all =
          catalog
              .map((item) => offer(item.offerId))
              .where(filter.matches)
              .toList()
            ..sort(filter.compare);
      final offset = (query.page - 1) * query.pageSize;
      final items = offset >= all.length
          ? <Offer>[]
          : all.skip(offset).take(query.pageSize).toList();
      if (duplicatePage && query.page == 2 && items.isNotEmpty) {
        items[0] = all.first;
      }
      return {
        'items': items.map((item) => item.toJson()).toList(),
        'page': PageInfo(
          page: query.page,
          pageSize: query.pageSize,
          total: all.length,
          hasNext: offset + items.length < all.length,
          nextCursor: offset + items.length < all.length
              ? 'page-${query.page + 1}'
              : null,
          previousCursor: query.page > 1 ? 'page-${query.page - 1}' : null,
        ).toJson(),
      };
    }
    if (op == ShareCoinOperation.offer ||
        op == ShareCoinOperation.offerStatus) {
      return offer(args['offerId'] as String).toJson();
    }
    if (op == ShareCoinOperation.startOffer) {
      final id = args['offerId'] as String;
      if (!offer(id).availableAt(offerTestTime)) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      return (starts[id] = OfferStart(
        startId: 'start-$id',
        offerId: id,
        userId: owner.userId,
        idempotencyKey: args['idempotencyKey'] as String,
        status: OfferStatus.started,
        updatedAt: offerTestTime,
      )).toJson();
    }
    if (op == ShareCoinOperation.adsConfiguration) {
      return AdConfiguration(
        rewardedEnabled: true,
        bannerEnabled: false,
        interstitialEnabled: false,
        cooldownSeconds: 60,
        dailyLimit: 5,
        premium: false,
        provider: 'test-provider',
        units: const {'rewarded': 'test-unit'},
      ).toJson();
    }
    if (op == ShareCoinOperation.dailyConfiguration) {
      return DailyRewardConfiguration(
        dayRewards: const [10, 20, 30, 40, 50, 60, 70],
        streakDay: 2,
        eligible: true,
        nextEligibleAt: offerTestTime,
        version: 'daily-policy',
      ).toJson();
    }
    if (op == ShareCoinOperation.submitReward) {
      if (rejectSignature) {
        throw ShareCoinException.fromServerCode('invalid_provider_signature');
      }
      final event = RewardEvent.fromJson(args);
      final ticket = sessions.values
          .where((ticket) => ticket.eventId == event.eventId)
          .firstOrNull;
      if (ticket == null ||
          ticket.userId != owner.userId ||
          event.requestedCoins != ticket.rewardCoins) {
        throw const ShareCoinException(CoinErrorCode.invalidRequest);
      }
      final json = event.toJson()..['status'] = RewardEventStatus.pending.name;
      rewardEvents[event.eventId] = RewardEvent.fromJson(json);
      if (approveImmediately) approve(ticket);
      return rewardEvents[event.eventId]!.toJson();
    }
    if (op == ShareCoinOperation.rewardStatus) {
      final event = rewardEvents[args['eventId']];
      if (event == null) throw const ShareCoinException(CoinErrorCode.notFound);
      return event.toJson();
    }
    if (op == ShareCoinOperation.transactions) {
      final query = OfferQuery.fromJson(args);
      final values = ledger.values.toList();
      final offset = (query.page - 1) * query.pageSize;
      final items = values.skip(offset).take(query.pageSize).toList();
      final more = offset + items.length < values.length;
      return {
        'items': items.map((item) => item.toJson()).toList(),
        'page': PageInfo(
          page: query.page,
          pageSize: query.pageSize,
          total: values.length,
          hasNext: more,
          nextCursor: more ? 'ledger-${query.page + 1}' : null,
        ).toJson(),
      };
    }
    if (op == ShareCoinOperation.promotions) {
      return page([promotion().toJson()], args);
    }
    return super.dataFor(op, owner, args);
  }

  Promotion promotion() => Promotion(
    campaignId: 'campaign-1',
    title: 'Test promotion',
    description: 'Fixture campaign, not an advertiser payout.',
    advertiser: 'Test advertiser',
    cta: 'Open test campaign',
    rewardCoins: 150,
    startsAt: offerTestTime.subtract(const Duration(days: 1)),
    endsAt: offerTestTime.add(const Duration(days: 1)),
    status: PromotionStatus.active,
    trackingId: 'campaign-track',
  );

  void approve(RewardSession ticket) {
    final previous =
        rewardEvents[ticket.eventId] ??
        RewardEvent(
          eventId: ticket.eventId,
          userId: ticket.userId,
          source: ticket.source,
          provider: ticket.provider,
          providerEventId: ticket.providerEventId ?? 'provider-event',
          targetId: ticket.targetId,
          requestedCoins: ticket.rewardCoins,
          occurredAt: offerTestTime,
          status: RewardEventStatus.pending,
          idempotencyKey: ticket.idempotencyKey,
        );
    final id = 'transaction-${ticket.sessionId}';
    if (!ledger.containsKey(id)) {
      // Emulates a backend ledger mutation in a test, never client wallet logic.
      balance += ticket.rewardCoins;
      ledger[id] = ShareCoinTransaction(
        transactionId: id,
        userId: ticket.userId,
        amount: ticket.rewardCoins,
        direction: CoinDirection.credit,
        source: ticket.source,
        status: CoinTransactionStatus.completed,
        description: 'Test backend credit.',
        createdAt: offerTestTime,
        completedAt: offerTestTime,
        referenceId: ticket.targetId,
        idempotencyKey: ticket.idempotencyKey,
      );
    }
    rewardEvents[ticket.eventId] = RewardEvent.fromJson(
      previous.toJson()
        ..['status'] = RewardEventStatus.approved.name
        ..['transactionId'] = id,
    );
  }

  @override
  Future<Map<String, dynamic>> executeRewardExtension(
    ShareCoinRewardOperation op,
    AccountScope owner,
    Map<String, Object?> args,
  ) async {
    extensionCalls[op] = (extensionCalls[op] ?? 0) + 1;
    if (extensionHandler != null) return extensionHandler!(op, owner, args);
    return extensionResponse(op, owner, args);
  }

  Map<String, dynamic> extensionResponse(
    ShareCoinRewardOperation op,
    AccountScope owner,
    Map<String, Object?> args,
  ) {
    switch (op) {
      case ShareCoinRewardOperation.offerLaunch:
        final start = starts.values
            .where((value) => value.startId == args['startId'])
            .firstOrNull;
        if (start == null) {
          throw const ShareCoinException(CoinErrorCode.notFound);
        }
        return envelope(
          owner,
          OfferLaunchGrant(
            startId: start.startId,
            offerId: start.offerId,
            userId: owner.userId,
            platform: coinEnum(
              args['platform'],
              OfferPlatform.values,
              'platform',
            ),
            url: launch,
            issuedAt: offerTestTime,
            expiresAt: offerTestTime.add(const Duration(minutes: 10)),
          ).toJson(),
        );
      case ShareCoinRewardOperation.prepareReward:
        final key = args['idempotencyKey'] as String;
        final existing = sessions.values
            .where((value) => value.requestKey == key)
            .firstOrNull;
        if (existing != null) return envelope(owner, existing.toJson());
        final number = sessions.length + 1;
        final source = coinEnum(args['source'], CoinSource.values, 'source');
        final session = RewardSession(
          sessionId: 'session-$number',
          userId: owner.userId,
          eventId: 'reward-$number',
          idempotencyKey: 'claim-$number',
          requestKey: key,
          source: source,
          provider: 'test-provider',
          targetId: args['targetId'] as String,
          rewardCoins: source == CoinSource.dailyReward ? 20 : 150,
          issuedAt: offerTestTime,
          expiresAt: offerTestTime.add(const Duration(minutes: 10)),
          notBefore: availability == RewardAvailability.cooldown
              ? offerTestTime.add(const Duration(seconds: 60))
              : offerTestTime,
          availability: availability,
          usedToday: used,
          dailyLimit: limit,
          providerEventId: source == CoinSource.dailyReward
              ? 'daily-server-event'
              : null,
          launchUrl: source == CoinSource.promotionReward ? launch : null,
        );
        sessions[session.sessionId] = session;
        return envelope(owner, session.toJson());
      case ShareCoinRewardOperation.sessionStatus:
        final session = sessions.values
            .where(
              (item) =>
                  args['sessionId'] == item.sessionId ||
                  args['requestKey'] == item.requestKey,
            )
            .firstOrNull;
        if (session == null) {
          throw const ShareCoinException(CoinErrorCode.notFound);
        }
        return envelope(owner, session.toJson());
      case ShareCoinRewardOperation.transaction:
        final transaction = ledger[args['transactionId']];
        if (transaction == null) {
          throw const ShareCoinException(CoinErrorCode.notFound);
        }
        return envelope(owner, transaction.toJson());
    }
  }
}

class TestRewardedAd implements RewardedAdAdapter {
  final StreamController<RewardedAdEvent> stream =
      StreamController<RewardedAdEvent>.broadcast(sync: true);
  RewardSession? loaded;
  int loads = 0, shows = 0, dismissals = 0;
  bool closed = false;
  Object? loadError;
  @override
  bool get configured => true;
  @override
  String get provider => 'test-provider';
  @override
  Stream<RewardedAdEvent> get events => stream.stream;
  @override
  Future<void> load(
    RewardSession session,
    AdConfiguration configuration,
  ) async {
    loads += 1;
    if (loadError != null) throw loadError!;
    loaded = session;
  }

  @override
  Future<void> show(String sessionId) async {
    shows += 1;
    stream.add(
      RewardedAdEvent(sessionId: sessionId, type: RewardedAdEventType.shown),
    );
  }

  void emit(
    RewardedAdEventType type, {
    String? sessionId,
    String? providerEvent,
  }) => stream.add(
    RewardedAdEvent(
      sessionId: sessionId ?? loaded!.sessionId,
      type: type,
      providerEventId: type == RewardedAdEventType.completed
          ? providerEvent ?? 'provider-event'
          : null,
    ),
  );
  @override
  Future<void> dismiss() async {
    dismissals += 1;
  }

  @override
  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    await stream.close();
  }
}

class OfferFixture {
  OfferFixture({int count = 300}) : backend = OfferTestBackend(count) {
    network = ConnectivityService(
      localProbe: () async => ['192.168.2.2'],
      internetProbe: () async => internet,
      serviceProbe: backend.checkService,
    );
    service = ShareCoinService(backend: backend, connectivity: network);
    controller = OfferwallController(
      service: service,
      policy: policy,
      clock: () => elapsed,
      launcher: (uri) async {
        launches.add(uri);
        return launchResult;
      },
    );
    rewards = RewardCoordinator(
      service: service,
      ad: ad,
      policy: policy,
      launcher: (uri) async {
        launches.add(uri);
        return launchResult;
      },
      clock: () => elapsed,
      autoTick: false,
    );
    addTearDown(() async {
      controller.dispose();
      rewards.dispose();
      service.dispose();
      network.dispose();
      await backend.close();
    });
  }
  final OfferTestBackend backend;
  final OfferResourcePolicy policy = OfferResourcePolicy(
    linkOrigins: const ['https://offers.example.org'],
  );
  final TestRewardedAd ad = TestRewardedAd();
  final List<Uri> launches = [];
  bool launchResult = true;
  InternetState internet = InternetState.available;
  Duration elapsed = Duration.zero;
  late final ConnectivityService network;
  late final ShareCoinService service;
  late final OfferwallController controller;
  late final RewardCoordinator rewards;
  void offline() {
    internet = InternetState.offline;
    backend.serviceState = CoinServiceState.unreachable;
  }
}

Future<void> settleReward(RewardCoordinator controller) async {
  if (!controller.value.busy) return;
  final done = Completer<void>();
  void listener() {
    if (!controller.value.busy && !done.isCompleted) done.complete();
  }

  controller.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
  } finally {
    controller.removeListener(listener);
  }
}

Future<void> mountOfferwall(
  WidgetTester tester,
  OfferFixture fixture, {
  Size size = const Size(390, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: OfferwallScreen(
        service: fixture.service,
        controller: fixture.controller,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Part 6 300-offer catalog', () {
    test('01 fixture has 300 unique lightweight offers and no live production source', () {
      final offers = createOfferFixture();
      expect(offers.length, 300);
      expect(offers.map((offer) => offer.offerId).toSet().length, 300);
      expect(
        offers.every((offer) => offer.description.contains('Fixture only')),
        isTrue,
      );
    });
    test(
      '02 pagination loads all 300 records from real service contracts',
      () async {
        final f = OfferFixture();
        await f.controller.refresh();
        while (f.controller.value.hasNext) {
          await f.controller.loadMore();
        }
        expect(f.controller.value.items.length, 300);
        expect(f.controller.value.total, 300);
        expect(f.backend.calls[ShareCoinOperation.offers], 15);
      },
    );
    test('03 cross-page duplicates are removed and disclosed', () async {
      final f = OfferFixture();
      f.backend.duplicatePage = true;
      await f.controller.refresh();
      await f.controller.loadMore();
      expect(f.controller.value.items.length, 39);
      expect(
        f.controller.value.items.map((item) => item.offerId).toSet().length,
        39,
      );
      expect(f.controller.value.message, contains('Duplicate'));
    });
    test('04 category and reward filters are passed to the backend', () async {
      final f = OfferFixture();
      f.controller.setFilter(
        OfferwallFilter(
          category: OfferCategory.games,
          minimumReward: 200,
          maximumReward: 260,
        ),
      );
      await f.controller.refresh();
      expect(f.controller.value.items, isNotEmpty);
      expect(
        f.controller.value.items.every(
          (item) =>
              item.category == OfferCategory.games &&
              item.rewardCoins >= 200 &&
              item.rewardCoins <= 260,
        ),
        isTrue,
      );
    });
    test('05 search works across a paginated catalog', () async {
      final f = OfferFixture();
      f.controller.setFilter(OfferwallFilter(search: 'Offer 299'));
      await f.controller.refresh();
      expect(f.controller.value.items.single.title, 'Offer 299');
    });
    test('06 all sorting modes use deterministic backend order', () async {
      final f = OfferFixture();
      for (final sort in OfferSort.values) {
        final filter = OfferwallFilter(sort: sort);
        f.controller.setFilter(filter);
        await f.controller.refresh();
        final expected = createOfferFixture().toList()..sort(filter.compare);
        expect(
          f.controller.value.items.map((item) => item.offerId),
          expected.take(20).map((item) => item.offerId),
        );
      }
    });
    test('07 expired offers cannot start or launch a link', () async {
      final f = OfferFixture();
      f.backend.forcedOfferStatus = OfferStatus.expired;
      await f.controller.start(f.backend.catalog.first);
      expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
      expect(f.launches, isEmpty);
    });
    test(
      '08 started and pending states do not imply credited reward',
      () async {
        final f = OfferFixture();
        final offer = f.backend.catalog.first;
        await f.controller.start(offer);
        expect(f.controller.statusOf(offer), OfferStatus.started);
        expect(f.controller.credits[offer.offerId], isNull);
        expect(f.backend.balance, 10000);
      },
    );
    test(
      '09 repeated start calls produce one backend start and launch',
      () async {
        final f = OfferFixture();
        final offer = f.backend.catalog.first;
        await Future.wait([
          f.controller.start(offer),
          f.controller.start(offer),
        ]);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
        expect(f.launches.length, 1);
        await f.controller.start(offer);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
      },
    );
    test('10 invalid offer responses are rejected', () async {
      final f = OfferFixture();
      f.backend.handler = (op, scope, args) async => f.backend.envelope(scope, {
        'items': [],
        'page': {'page': -1},
      });
      await f.controller.refresh();
      expect(f.controller.value.state, OfferLoadState.error);
      expect(f.controller.value.items, isEmpty);
    });
    test(
      '27 offline catalog exposes cached data without starting offline offers',
      () async {
        final f = OfferFixture();
        await f.controller.refresh();
        f.offline();
        await f.controller.refresh();
        expect(f.controller.value.cached, isTrue);
        expect(f.controller.value.items.length, 20);
        await f.controller.start(f.backend.catalog.first);
        expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
      },
    );
    test('32 end state prevents further requests', () async {
      final f = OfferFixture(count: 5);
      await f.controller.refresh();
      await f.controller.loadMore();
      expect(f.controller.value.hasNext, isFalse);
      expect(f.backend.calls[ShareCoinOperation.offers], 1);
    });
    test('bounded windows can traverse more than 1000 offers', () async {
      final f = OfferFixture(count: 1020);
      await f.controller.refresh();
      var found = 0;
      while (true) {
        if (f.controller.value.windowFull || !f.controller.value.hasNext) {
          found += f.controller.value.items.length;
          expect(f.controller.value.items.length, lessThanOrEqualTo(500));
          if (!f.controller.value.hasNext) break;
          await f.controller.nextWindow();
        } else {
          await f.controller.loadMore();
        }
      }
      expect(found, 1020);
    });
    test('unknown offer IDs never reach start mutation', () async {
      final f = OfferFixture();
      final unknown = createOfferFixture(1).first.toJson()
        ..['offerId'] = 'unknown-id';
      await f.controller.start(Offer.fromJson(unknown));
      expect(f.backend.calls[ShareCoinOperation.startOffer] ?? 0, 0);
    });
    test('unsafe backend launch grants are not opened', () async {
      final f = OfferFixture();
      f.backend.launch = Uri.parse('https://untrusted.example.org/task');
      await f.controller.start(f.backend.catalog.first);
      expect(f.launches, isEmpty);
    });
    test('completion label uses a matching completed ledger transaction, not nominal reward', () async {
      final f = OfferFixture();
      final offer = f.backend.catalog.first;
      f.backend.offerTransactions[offer.offerId] = 'offer-tx';
      f.backend.ledger['offer-tx'] = ShareCoinTransaction(
        transactionId: 'offer-tx',
        userId: 'user-1',
        amount: 175,
        direction: CoinDirection.credit,
        source: CoinSource.offerReward,
        status: CoinTransactionStatus.completed,
        description: 'Test completed credit.',
        createdAt: offerTestTime,
        completedAt: offerTestTime,
        referenceId: offer.offerId,
        idempotencyKey: 'offer-credit-key',
      );
      await f.controller.refreshOffer(offer.offerId);
      expect(f.controller.statusLabel(offer), 'Completed +175 ShareCoin');
    });
    test(
      '36 malformed ledger linkage cannot confirm an offer reward',
      () async {
        final f = OfferFixture();
        final offer = f.backend.catalog.first;
        f.backend.offerTransactions[offer.offerId] = 'wrong-tx';
        f.backend.ledger['wrong-tx'] = p5.coinFixtureTransaction();
        await f.controller.refreshOffer(offer.offerId);
        expect(
          f.controller.credits[offer.offerId]?.state,
          isNot(RewardCreditState.credited),
        );
      },
    );
  });

  group('Part 6 reward authority', () {
    test('11 invalid reward sessions reject negative amount and impossible eligibility', () {
      expect(
        () => RewardSession(
          sessionId: 's',
          userId: 'u',
          eventId: 'e',
          idempotencyKey: 'k',
          requestKey: 'r',
          source: CoinSource.adReward,
          provider: 'p',
          targetId: 't',
          rewardCoins: -1,
          issuedAt: offerTestTime,
          expiresAt: offerTestTime.add(const Duration(minutes: 1)),
          notBefore: offerTestTime,
          availability: RewardAvailability.eligible,
          usedToday: 0,
          dailyLimit: 5,
        ),
        throwsA(isA<CoinModelException>()),
      );
    });
    test('12 provider completion alone remains backend pending, with unchanged wallet', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      expect(f.rewards.value.phase, RewardPhase.ready);
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      expect(f.rewards.value.phase, RewardPhase.rewardPending);
      expect(f.backend.balance, 10000);
    });
    test(
      '13 duplicate ad callbacks cannot submit multiple reward events',
      () async {
        final f = OfferFixture();
        await f.rewards.loadAd();
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed);
        f.ad.emit(RewardedAdEventType.completed);
        await settleReward(f.rewards);
        expect(f.backend.calls[ShareCoinOperation.submitReward], 1);
      },
    );
    test('14 backend cooldown uses monotonic elapsed time and cannot be bypassed by repeated taps', () async {
      final f = OfferFixture();
      f.backend.availability = RewardAvailability.cooldown;
      await f.rewards.loadAd();
      expect(f.rewards.value.phase, RewardPhase.cooldown);
      f.elapsed = const Duration(seconds: 30);
      f.rewards.refreshClock();
      expect(f.rewards.value.cooldownRemaining.inSeconds, 30);
      await f.rewards.loadAd();
      expect(
        f.backend.extensionCalls[ShareCoinRewardOperation.prepareReward],
        1,
      );
      expect(f.ad.loads, 0);
    });
    test(
      '15 daily ad limit is a backend decision, not a local reset',
      () async {
        final f = OfferFixture();
        f.backend.availability = RewardAvailability.dailyLimit;
        f.backend.used = 5;
        await f.rewards.loadAd();
        expect(f.rewards.value.phase, RewardPhase.dailyLimit);
        expect(f.ad.loads, 0);
      },
    );
    test('16 daily claim uses a server-issued reference and backend event validation', () async {
      final f = OfferFixture();
      await f.rewards.claimDaily();
      expect(f.rewards.value.phase, RewardPhase.rewardPending);
      expect(
        f.backend.rewardEvents.values.single.providerEventId,
        'daily-server-event',
      );
      expect(f.backend.balance, 10000);
    });
    test('17 expired promotions cannot launch or credit', () async {
      final f = OfferFixture();
      final json = f.backend.promotion().toJson()
        ..['endsAt'] = offerTestTime
            .subtract(const Duration(hours: 1))
            .toIso8601String();
      await f.rewards.startPromotion(Promotion.fromJson(json));
      expect(f.launches, isEmpty);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    test(
      'promotion clicks create tracking only, never a reward event',
      () async {
        final f = OfferFixture();
        await f.rewards.startPromotion(f.backend.promotion());
        expect(f.rewards.value.phase, RewardPhase.tracking);
        expect(f.launches.length, 1);
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        expect(f.backend.balance, 10000);
      },
    );
    test('backend approval requires completed matching transaction before credit display', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      f.backend.approve(f.backend.sessions.values.single);
      await f.rewards.refreshStatus();
      expect(f.rewards.value.credited, isTrue);
      expect(f.rewards.value.transaction!.amount, 150);
      expect(f.backend.calls[ShareCoinOperation.wallet], greaterThan(0));
    });
    test(
      'invalid provider signature reported by backend never credits',
      () async {
        final f = OfferFixture();
        f.backend.rejectSignature = true;
        await f.rewards.loadAd();
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed);
        await settleReward(f.rewards);
        expect(f.rewards.value.phase, RewardPhase.rejected);
        expect(f.backend.balance, 10000);
        expect(f.backend.ledger, isEmpty);
      },
    );
    test('24 reversed ledger transactions remain visible and are not approved credits', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      f.backend.approve(f.backend.sessions.values.single);
      final old = f.backend.ledger.values.single;
      f.backend.ledger[old.transactionId] = ShareCoinTransaction.fromJson(
        old.toJson()..['status'] = CoinTransactionStatus.reversed.name,
      );
      await f.rewards.refreshStatus();
      expect(f.rewards.value.phase, RewardPhase.reversed);
      expect(f.rewards.value.credited, isFalse);
    });
    test('25 and 26 negative or overflowing callback amounts cannot enter the domain', () {
      for (final amount in <int>[-1, maxShareCoinInteger + 1]) {
        expect(
          () => p5.coinFixtureReward(coins: amount),
          throwsA(isA<CoinModelException>()),
        );
      }
    });
    test('28 offline reward flow does not send events or show ads', () async {
      final f = OfferFixture()..offline();
      await f.rewards.loadAd();
      expect(f.ad.loads, 0);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
    });
    test(
      '37 stale session callbacks and completion before show are ignored',
      () async {
        final f = OfferFixture();
        await f.rewards.loadAd();
        f.ad.emit(RewardedAdEventType.completed);
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed, sessionId: 'stale-session');
        expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
        f.ad.emit(RewardedAdEventType.skipped);
        expect(f.rewards.value.phase, RewardPhase.skipped);
      },
    );
    test('38 background interruption discards callbacks but retains reconciliation identity', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.rewards.suspend();
      f.ad.emit(RewardedAdEventType.completed);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      expect(f.rewards.value.phase, RewardPhase.interrupted);
      f.rewards.resume();
      await f.rewards.refreshStatus();
      expect(f.rewards.value.phase, RewardPhase.tracking);
    });
    test('account switch rejects an old provider completion', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.backend.switchAccount(
        AccountScope(userId: 'user-2', sessionId: 'login-2'),
      );
      f.ad.emit(RewardedAdEventType.completed);
      await Future<void>.delayed(Duration.zero);
      expect(f.backend.calls[ShareCoinOperation.submitReward] ?? 0, 0);
      expect(f.rewards.value.session, isNull);
    });
    test('provider load failure is not a completed ad', () async {
      final f = OfferFixture();
      f.ad.loadError = const ShareCoinException(CoinErrorCode.unavailable);
      await f.rewards.loadAd();
      expect(f.rewards.value.phase, RewardPhase.failed);
      expect(f.rewards.canShow, isFalse);
    });
    test('unconfigured ad adapter never simulates playback', () async {
      final f = OfferFixture();
      final coordinator = RewardCoordinator(
        service: f.service,
        autoTick: false,
      );
      addTearDown(coordinator.dispose);
      await coordinator.loadAd();
      expect(coordinator.value.phase, RewardPhase.failed);
      expect(
        f.backend.extensionCalls[ShareCoinRewardOperation.prepareReward] ?? 0,
        0,
      );
    });
  });

  group('Part 6 consent and receipt regressions', () {
    test(
      'a grant expiring while the user reviews consent is not launched',
      () async {
        final f = OfferFixture();
        await f.controller.start(
          f.backend.catalog.first,
          consent: (uri) async {
            f.elapsed = const Duration(minutes: 20);
            return true;
          },
        );
        expect(f.launches, isEmpty);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
      },
    );
    test(
      'late provider errors do not erase a backend-confirmed credit',
      () async {
        final f = OfferFixture();
        f.backend.approveImmediately = true;
        await f.rewards.loadAd();
        await f.rewards.showAd();
        f.ad.emit(RewardedAdEventType.completed);
        await settleReward(f.rewards);
        expect(f.rewards.value.credited, isTrue);
        f.ad.stream.addError(StateError('late provider notification'));
        expect(f.rewards.value.credited, isTrue);
      },
    );
    test('a pending provider claim cannot load a second ad session', () async {
      final f = OfferFixture();
      await f.rewards.loadAd();
      await f.rewards.showAd();
      f.ad.emit(RewardedAdEventType.completed);
      await settleReward(f.rewards);
      await f.rewards.loadAd();
      expect(f.ad.loads, 1);
      expect(
        f.backend.extensionCalls[ShareCoinRewardOperation.prepareReward],
        1,
      );
    });
  });

  group('Part 6 retained account and withdrawal safety', () {
    test('18 referral model preserves server qualification and rejects impossible totals', () {
      expect(
        () => ReferralSummary(
          userId: 'u',
          referralCode: 'ref',
          invitedCount: 1,
          pendingCount: 2,
          qualifiedCount: 1,
          earnedCoins: 1,
          status: ReferralStatus.active,
          updatedAt: offerTestTime,
        ),
        throwsA(isA<CoinModelException>()),
      );
    });
    test('19 minimum and 20 balance remain backend-policy checks', () async {
      final f = p5.CoinServiceFixture();
      await expectLater(
        f.service.requestWithdrawal(p5.coinFixtureIntent(coins: 500)),
        throwsA(p5.coinError(CoinErrorCode.minimum)),
      );
      await expectLater(
        f.service.requestWithdrawal(p5.coinFixtureIntent(coins: 11000)),
        throwsA(p5.coinError(CoinErrorCode.insufficientBalance)),
      );
      expect(f.backend.calls[ShareCoinOperation.requestWithdrawal] ?? 0, 0);
    });
    test(
      '21 and 22 duplicate withdrawal request keys still coalesce',
      () async {
        final f = p5.CoinServiceFixture();
        final intent = p5.coinFixtureIntent();
        await Future.wait([
          f.service.requestWithdrawal(intent),
          f.service.requestWithdrawal(intent),
        ]);
        expect(f.backend.calls[ShareCoinOperation.requestWithdrawal], 1);
        expect(f.backend.balance, 10000);
      },
    );
    test('23 all transaction source/status values round trip', () {
      for (final source in CoinSource.values) {
        for (final status in CoinTransactionStatus.values) {
          final transaction = p5.coinFixtureTransaction(
            source: source,
            status: status,
          );
          expect(
            ShareCoinTransaction.fromJson(transaction.toJson()).toJson(),
            transaction.toJson(),
          );
        }
      }
    });
    test(
      '29 local Wi-Fi remains distinct from unavailable internet rewards',
      () async {
        final f = OfferFixture()..offline();
        await f.network.refresh();
        expect(f.network.value.hasLocalCandidate, isTrue);
        expect(f.network.value.canRequestRewards, isFalse);
      },
    );
    test(
      '35 backend errors are safely mapped without exposing provider secrets',
      () {
        expect(
          ShareCoinException.fromServerCode('invalid_provider_signature').code,
          CoinErrorCode.invalidRequest,
        );
        expect(
          ShareCoinException.fromServerCode('private_stack').message,
          isNot(contains('private_stack')),
        );
      },
    );
  });

  group('Part 6 images and lifecycle UI', () {
    testWidgets('31 search debounce discards intermediate queries', (
      tester,
    ) async {
      final f = OfferFixture();
      await mountOfferwall(tester, f);
      final before = f.backend.calls[ShareCoinOperation.offers]!;
      await tester.enterText(
        find.byKey(const ValueKey('offer-search')),
        'Offer 2',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(
        find.byKey(const ValueKey('offer-search')),
        'Offer 299',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(f.backend.calls[ShareCoinOperation.offers], before);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(f.controller.value.items.single.title, 'Offer 299');
      expect(f.backend.calls[ShareCoinOperation.offers], before + 1);
    });
    testWidgets(
      '33 all 300 offers can be scrolled with lazy card construction',
      (tester) async {
        final f = OfferFixture();
        await mountOfferwall(tester, f);
        for (
          var index = 0;
          index < 300 && f.controller.value.hasNext;
          index += 1
        ) {
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -1500),
          );
          await tester.pumpAndSettle();
        }
        expect(f.controller.value.items.length, 300);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('offer-end')),
          1800,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('offer-end')), findsOneWidget);
        expect(find.byType(OfferThumbnail).evaluate().length, lessThan(30));
      },
    );
    testWidgets('34 malformed images fall back without breaking a card', (
      tester,
    ) async {
      final policy = OfferResourcePolicy(
        imageOrigins: const ['https://assets.example.org'],
      );
      final cache = OfferThumbnailCache(
        policy: policy,
        canFetch: () => true,
        fetchBytes: (uri) async => Uint8List.fromList([1, 2, 3]),
      );
      addTearDown(cache.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfferThumbnail(
              cache: cache,
              uri: Uri.parse('https://assets.example.org/bad.png'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await cache.get(Uri.parse('https://assets.example.org/bad.png'));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    });
    testWidgets(
      'thumbnail cache is bounded and shared rather than loading 300 images at once',
      (tester) async {
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGMUyw76z8DAwMDEAAUAGxwB1s7iOpcAAAAASUVORK5CYII=',
        );
        var active = 0, maximum = 0, calls = 0;
        final cache = OfferThumbnailCache(
          policy: OfferResourcePolicy(
            imageOrigins: const ['https://assets.example.org'],
          ),
          canFetch: () => true,
          maxEntries: 2,
          parallelism: 2,
          fetchBytes: (uri) async {
            active += 1;
            calls += 1;
            if (active > maximum) maximum = active;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            active -= 1;
            return bytes;
          },
        );
        addTearDown(cache.dispose);
        await tester.runAsync(() async {
          final uri = Uri.parse('https://assets.example.org/one.png');
          final pair = await Future.wait([cache.get(uri), cache.get(uri)]);
          expect(pair.first, isNotNull);
          expect(calls, 1);
          await Future.wait(
            List.generate(
              6,
              (i) => cache.get(Uri.parse('https://assets.example.org/$i.png')),
            ),
          );
        });
        expect(maximum, lessThanOrEqualTo(2));
        expect(cache.entryCount, lessThanOrEqualTo(2));
        expect(cache.cachedBytes, lessThanOrEqualTo(cache.maxBytes));
      },
    );
    test('resource policy blocks untrusted origins and unsafe URL schemes', () {
      final policy = OfferResourcePolicy(
        linkOrigins: const ['https://offers.example.org'],
      );
      for (final input in [
        'http://offers.example.org/a',
        'https://offers.example.org.evil/a',
        'javascript:alert(1)',
        'file:///secret',
        'https://user:pass@offers.example.org/a',
      ]) {
        expect(policy.allowsLink(Uri.parse(input)), isFalse);
      }
      expect(
        policy.allowsLink(Uri.parse('https://offers.example.org/task')),
        isTrue,
      );
    });
    testWidgets(
      'detail requires tracking consent and returns no reward merely for opening',
      (tester) async {
        final f = OfferFixture(count: 1);
        await mountOfferwall(tester, f);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('open-offer-offer-0000')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('open-offer-offer-0000'),
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('start-detailed-offer')),
              )
              .onPressed,
          isNull,
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('offer-tracking-consent'),
        );
        await baseline.tapVisibleKey(
          tester,
          const ValueKey('start-detailed-offer'),
        );
        expect(find.text('Open provider destination?'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(f.launches, isEmpty);
        expect(f.backend.calls[ShareCoinOperation.startOffer], 1);
        expect(f.backend.balance, 10000);
      },
    );
    testWidgets('30 disposing offer UI safely detaches ongoing reads', (
      tester,
    ) async {
      final f = OfferFixture();
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      f.backend.handler = (op, scope, args) async {
        if (op == ShareCoinOperation.offers) {
          started.complete();
          return pending.future;
        }
        return f.backend.envelope(scope, f.backend.dataFor(op, scope, args));
      };
      await tester.pumpWidget(
        MaterialApp(
          home: OfferwallScreen(service: f.service, controller: f.controller),
        ),
      );
      for (var i = 0; i < 50 && !started.isCompleted; i += 1) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(started.isCompleted, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
      pending.complete(
        f.backend.envelope(
          f.backend.scope!,
          f.backend.dataFor(
            ShareCoinOperation.offers,
            f.backend.scope!,
            OfferQuery().toJson(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'large text on a narrow screen keeps featured cards and controls usable',
      (tester) async {
        final f = OfferFixture();
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await mountOfferwall(tester, f, size: const Size(320, 740));
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '39 unified navigation retains the original file-sharing home',
      (tester) async {
        final f = OfferFixture();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              pickFiles: () async => FileSelection(files: []),
              onToggleTheme: () {},
              shareCoinScreenBuilder: (context) => ShareCoinHomeScreen(
                service: f.service,
                offerPolicy: f.policy,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-share-coin')));
        await tester.pumpAndSettle();
        await p5.tapCoinKey(tester, 'coin-offers');
        expect(find.byKey(const ValueKey('offerwall-screen')), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('select-files-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('receive-files-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('saved-files-button')),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      '40 existing withdrawal UI remains reachable with no real-provider claim',
      (tester) async {
        final service = ShareCoinService(
          connectivity: ConnectivityService(localProbe: () async => []),
        );
        addTearDown(service.connectivity.dispose);
        addTearDown(service.dispose);
        await p5.mountCoinDashboard(tester, service);
        await p5.tapCoinKey(tester, 'coin-withdraw');
        expect(find.text('Withdrawals unavailable'), findsOneWidget);
        expect(
          find.textContaining('configuration options only'),
          findsOneWidget,
        );
      },
    );
  });
}
```

## Required integration replacements

## File 1 — `pubspec.yaml` — UPDATED

```yaml
name: sharebondhu
description: "ShareBondhu - nearby file sharing, built step by step."
publish_to: "none"
version: 0.6.0+6

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  file_picker: 12.2.0
  basic_utils: 5.8.2
  crypto: 3.0.7
  path_provider: 2.1.6
  share_plus: 13.3.0
  qr_flutter: 4.1.0
  mobile_scanner: 7.4.0
  path: 1.9.1
  url_launcher: 6.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 6.0.0

flutter:
  uses-material-design: true
```

## File 23 — `lib/services/share_coin_service.dart` — UPDATED

```dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import '../models/offerwall_models.dart';
import 'connectivity_service.dart';

enum ShareCoinOperation {
  currentUser,
  wallet,
  transactions,
  submitReward,
  rewardStatus,
  rewardHistory,
  offers,
  offer,
  startOffer,
  offerStatus,
  promotions,
  withdrawalPolicy,
  requestWithdrawal,
  withdrawals,
  withdrawalStatus,
  withdrawalByKey,
  referral,
  adsConfiguration,
  dailyConfiguration,
}

enum CoinErrorCode {
  notConfigured,
  unauthenticated,
  restricted,
  offline,
  unavailable,
  malformed,
  accountChanged,
  invalidRequest,
  conflict,
  minimum,
  insufficientBalance,
  payoutUnavailable,
  policyChanged,
  notFound,
  rateLimited,
  uncertain,
  disposed,
}

enum CoinDataOrigin { server, cache }

class ShareCoinException implements Exception {
  const ShareCoinException(this.code);
  final CoinErrorCode code;
  bool get outcomeUncertain => code == CoinErrorCode.uncertain;
  String get message => switch (code) {
    CoinErrorCode.notConfigured => 'ShareCoin backend is not configured. No real balance or payout is available.',
    CoinErrorCode.unauthenticated =>
      'Account setup and backend authentication are required.',
    CoinErrorCode.restricted =>
      'This account cannot request rewards or withdrawals.',
    CoinErrorCode.offline =>
      'Reward services are offline. Local file sharing is separate.',
    CoinErrorCode.unavailable =>
      'The ShareCoin service is unavailable. Try a status refresh.',
    CoinErrorCode.malformed => 'The backend response could not be validated.',
    CoinErrorCode.accountChanged =>
      'The account changed. Refresh before continuing.',
    CoinErrorCode.invalidRequest =>
      'The request is invalid. Review the amount and request details.',
    CoinErrorCode.conflict => 'This action is already pending or the request key was reused with different data.',
    CoinErrorCode.minimum =>
      'The amount is below the backend withdrawal minimum.',
    CoinErrorCode.insufficientBalance =>
      'The backend wallet does not have enough available coins.',
    CoinErrorCode.payoutUnavailable =>
      'This payout method or saved destination is not connected.',
    CoinErrorCode.policyChanged =>
      'The payout policy changed. Refresh and review the new quote.',
    CoinErrorCode.notFound => 'The backend did not return this record.',
    CoinErrorCode.rateLimited => 'Too many requests. Wait before trying again.',
    CoinErrorCode.uncertain => 'Confirmation was lost. Check the request status instead of creating another request.',
    CoinErrorCode.disposed => 'This ShareCoin session is closed.',
  };
  factory ShareCoinException.fromServerCode(String code) =>
      ShareCoinException(switch (code) {
        'unauthenticated' => CoinErrorCode.unauthenticated,
        'restricted' => CoinErrorCode.restricted,
        'conflict' => CoinErrorCode.conflict,
        'below_minimum' => CoinErrorCode.minimum,
        'insufficient_balance' => CoinErrorCode.insufficientBalance,
        'payout_unavailable' => CoinErrorCode.payoutUnavailable,
        'policy_changed' => CoinErrorCode.policyChanged,
        'not_found' => CoinErrorCode.notFound,
        'rate_limited' => CoinErrorCode.rateLimited,
        'invalid_request' ||
        'invalid_provider_signature' ||
        'expired_offer' => CoinErrorCode.invalidRequest,
        'cooldown' || 'daily_limit' => CoinErrorCode.rateLimited,
        'duplicate_event' => CoinErrorCode.conflict,
        _ => CoinErrorCode.unavailable,
      });
  @override
  String toString() => message;
}

class CoinData<T> {
  const CoinData({
    required this.data,
    required this.origin,
    required this.serverTime,
    required this.version,
    required this.accountKey,
  });
  final T data;
  final CoinDataOrigin origin;
  final DateTime serverTime;
  final String version, accountKey;
  bool get cached => origin == CoinDataOrigin.cache;
  CoinData<T> asCached() => CoinData<T>(
    data: data,
    origin: CoinDataOrigin.cache,
    serverTime: serverTime,
    version: version,
    accountKey: accountKey,
  );
}

// A real adapter must authenticate every operation, bound response sizes, use
// verified HTTPS, and enforce the documented backend ledger/idempotency rules.
// No URL, credential store, authentication provider or remote server is invented.
abstract interface class ShareCoinBackend {
  bool get configured;
  AccountScope? get scope;
  Stream<AccountScope?> get accountChanges;
  Future<CoinServiceState> checkService();
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  );
}

// Optional capability on the SAME authenticated backend, not another wallet.
enum ShareCoinRewardOperation {
  transaction,
  prepareReward,
  sessionStatus,
  offerLaunch,
}

abstract interface class ShareCoinRewardBackend implements ShareCoinBackend {
  Future<Map<String, dynamic>> executeRewardExtension(
    ShareCoinRewardOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  );
}

class UnconfiguredShareCoinBackend implements ShareCoinBackend {
  const UnconfiguredShareCoinBackend();
  @override
  bool get configured => false;
  @override
  AccountScope? get scope => null;
  @override
  Stream<AccountScope?> get accountChanges =>
      const Stream<AccountScope?>.empty();
  @override
  Future<CoinServiceState> checkService() async =>
      CoinServiceState.unconfigured;
  @override
  Future<Map<String, dynamic>> execute(
    ShareCoinOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  ) => Future<Map<String, dynamic>>.error(
    const ShareCoinException(CoinErrorCode.notConfigured),
  );
}

class _CoinMutation {
  _CoinMutation(this.fingerprint, this.key, this.future);
  final String fingerprint, key;
  final Future<Object> future;
  final Set<String> aliases = <String>{};
  bool settled = false;
  bool uncertain = false;
}

String newCoinRequestId() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ShareCoinService extends ChangeNotifier {
  ShareCoinService({
    ShareCoinBackend? backend,
    ConnectivityService? connectivity,
    this.requestTimeout = const Duration(seconds: 15),
    this.cachePages = 24,
    this.mutationLimit = 256,
  }) {
    if (requestTimeout <= Duration.zero ||
        cachePages < 1 ||
        mutationLimit < 1) {
      throw ArgumentError('Service limits must be positive.');
    }
    _backend = backend ?? const UnconfiguredShareCoinBackend();
    _ownsConnectivity = connectivity == null;
    this.connectivity =
        connectivity ??
        ConnectivityService(
          serviceProbe: _backend.configured ? _backend.checkService : null,
        );
    _accountKey = _backend.scope?.key;
    _accountSubscription = _backend.accountChanges.listen(
      (_) => _synchronizeAccount(),
      onError: (Object error, StackTrace stack) {
        _clearAccountState();
      },
    );
  }
  late final ShareCoinBackend _backend;
  late final ConnectivityService connectivity;
  late final bool _ownsConnectivity;
  late final StreamSubscription<AccountScope?> _accountSubscription;
  final Duration requestTimeout;
  final int cachePages, mutationLimit;
  final LinkedHashMap<String, CoinData<Object>> _cache =
      LinkedHashMap<String, CoinData<Object>>();
  final Map<String, Future<Object>> _reads = <String, Future<Object>>{};
  final LinkedHashMap<String, _CoinMutation> _mutations =
      LinkedHashMap<String, _CoinMutation>();
  final Map<String, String> _aliases = <String, String>{};
  final Map<String, WithdrawalRequest> _withdrawalStates =
      <String, WithdrawalRequest>{};
  String? _accountKey;
  String? _withdrawalLock;
  String? _activeWithdrawalId;
  int _generation = 0;
  int _walletGeneration = 0;
  bool _closed = false;
  bool _suspended = false;

  bool get backendConfigured => _backend.configured;
  String? get accountKey => _backend.scope?.key;
  bool get hasAccount => _backend.scope != null;
  bool get hasPendingWithdrawal =>
      _withdrawalLock != null || _activeWithdrawalId != null;
  CoinData<ShareCoinBalance>? get cachedWallet {
    final scope = _backend.scope;
    if (scope == null || scope.key != _accountKey) return null;
    return (_cache[_key(scope, ShareCoinOperation.wallet, const {})]
            as CoinData<ShareCoinBalance>?)
        ?.asCached();
  }

  void _synchronizeAccount() {
    if (_closed) return;
    final key = _backend.scope?.key;
    if (key != _accountKey) {
      _clearAccountState(nextKey: key);
    }
  }

  void _clearAccountState({String? nextKey}) {
    if (_closed) return;
    _generation += 1;
    _walletGeneration += 1;
    _accountKey = nextKey;
    _cache.clear();
    _reads.clear();
    _mutations.clear();
    _aliases.clear();
    _withdrawalStates.clear();
    _withdrawalLock = null;
    _activeWithdrawalId = null;
    notifyListeners();
  }

  AccountScope _scope() {
    if (_closed) throw const ShareCoinException(CoinErrorCode.disposed);
    if (!_backend.configured) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    _synchronizeAccount();
    final scope = _backend.scope;
    if (scope == null) {
      throw const ShareCoinException(CoinErrorCode.unauthenticated);
    }
    return scope;
  }

  void _current(AccountScope scope, int generation) {
    if (_closed) throw const ShareCoinException(CoinErrorCode.disposed);
    if (generation != _generation || _backend.scope?.key != scope.key) {
      throw const ShareCoinException(CoinErrorCode.accountChanged);
    }
  }

  Future<void> _online(AccountScope scope, int generation) async {
    if (_suspended) throw const ShareCoinException(CoinErrorCode.offline);
    await connectivity.refresh();
    _current(scope, generation);
    if (_suspended || !connectivity.value.canRequestRewards) {
      throw ShareCoinException(
        connectivity.value.internet == InternetState.offline
            ? CoinErrorCode.offline
            : CoinErrorCode.unavailable,
      );
    }
  }

  String _key(
    AccountScope scope,
    ShareCoinOperation operation,
    Map<String, Object?> args,
  ) => '${scope.key}|${operation.name}|${jsonEncode(_canonical(args))}';
  Object? _canonical(Object? input) {
    if (input is Map) {
      final keys = input.keys.cast<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(input[key]),
      };
    }
    if (input is List) return input.map(_canonical).toList();
    return input;
  }

  Future<CoinData<T>> _execute<T extends Object>(
    AccountScope scope,
    int generation,
    ShareCoinOperation operation,
    Map<String, Object?> arguments,
    T Function(Map<String, dynamic>, AccountScope) parse, {
    bool mutation = false,
    Future<Map<String, dynamic>> Function()? request,
  }) async {
    try {
      _current(scope, generation);
      if (mutation && _suspended) {
        throw const ShareCoinException(CoinErrorCode.offline);
      }
      final response = request != null
          ? request()
          : _backend.execute(
              operation,
              scope,
              Map<String, Object?>.unmodifiable(arguments),
            );
      final envelope = await response.timeout(requestTimeout);
      _current(scope, generation);
      if (coinId(envelope['userId'], 'userId') != scope.userId) {
        throw const CoinModelException('response account');
      }
      final serverTime = coinTime(envelope['serverTime'], 'serverTime');
      final version = coinId(envelope['version'], 'version');
      final value = parse(coinObject(envelope['data'], 'data'), scope);
      return CoinData<T>(
        data: value,
        origin: CoinDataOrigin.server,
        serverTime: serverTime,
        version: version,
        accountKey: scope.key,
      );
    } on ShareCoinException catch (error) {
      if (mutation &&
          <CoinErrorCode>{
            CoinErrorCode.offline,
            CoinErrorCode.unavailable,
            CoinErrorCode.malformed,
          }.contains(error.code)) {
        throw const ShareCoinException(CoinErrorCode.uncertain);
      }
      rethrow;
    } on CoinModelException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.malformed,
      );
    } on SocketException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.unavailable,
      );
    } on HandshakeException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.unavailable,
      );
    } on TimeoutException {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.unavailable,
      );
    } catch (_) {
      throw ShareCoinException(
        mutation ? CoinErrorCode.uncertain : CoinErrorCode.malformed,
      );
    }
  }

  T _owned<T>(T object, String userId, AccountScope scope) {
    if (userId != scope.userId) {
      throw const CoinModelException('record account');
    }
    return object;
  }

  Future<CoinData<T>> _read<T extends Object>(
    ShareCoinOperation operation,
    T Function(Map<String, dynamic>, AccountScope) parse, {
    Map<String, Object?> arguments = const {},
    bool allowCached = true,
    Future<Map<String, dynamic>> Function(AccountScope, Map<String, Object?>)?
    request,
  }) {
    try {
      final scope = _scope();
      final generation = _generation;
      final walletGeneration = _walletGeneration;
      final key = _key(scope, operation, arguments);
      final readKey = '$key|${allowCached ? 'cache-ok' : 'server-only'}';
      final current = _reads[readKey];
      if (current != null) return current.then((value) => value as CoinData<T>);
      final completion = Completer<CoinData<T>>();
      _reads[readKey] = completion.future;
      Future<void>(() async {
        try {
          await _online(scope, generation);
          final data = await _execute(
            scope,
            generation,
            operation,
            arguments,
            parse,
            request: request == null ? null : () => request(scope, arguments),
          );
          _current(scope, generation);
          if (operation == ShareCoinOperation.wallet &&
              walletGeneration != _walletGeneration) {
            throw const ShareCoinException(CoinErrorCode.unavailable);
          }
          final old = _cache[key];
          if (old != null && data.serverTime.isBefore(old.serverTime)) {
            throw const ShareCoinException(CoinErrorCode.malformed);
          }
          if (data.data is CoinPage) {
            final page = data.data as CoinPage;
            if (page.info.page != arguments['page'] ||
                page.info.pageSize != arguments['pageSize'] ||
                (page.info.hasNext &&
                    page.info.nextCursor != null &&
                    page.info.nextCursor == arguments['cursor'])) {
              throw const ShareCoinException(CoinErrorCode.malformed);
            }
          }
          _cache.remove(key);
          _cache[key] = data;
          while (_cache.length > cachePages) {
            _cache.remove(_cache.keys.first);
          }
          completion.complete(data);
        } catch (error) {
          final cached = _cache[key];
          final canCache =
              error is ShareCoinException &&
              <CoinErrorCode>{
                CoinErrorCode.offline,
                CoinErrorCode.unavailable,
              }.contains(error.code);
          if (allowCached &&
              canCache &&
              cached != null &&
              !_closed &&
              _backend.scope?.key == scope.key &&
              generation == _generation) {
            completion.complete((cached as CoinData<T>).asCached());
          } else {
            completion.completeError(error);
          }
        } finally {
          if (identical(_reads[readKey], completion.future)) {
            _reads.remove(readKey);
          }
        }
      });
      return completion.future;
    } catch (error) {
      return Future<CoinData<T>>.error(error);
    }
  }

  Future<CoinData<ShareCoinUser>> getCurrentUser({bool allowCached = true}) =>
      _read(ShareCoinOperation.currentUser, (j, scope) {
        final user = ShareCoinUser.fromJson(j);
        return _owned(user, user.userId, scope);
      }, allowCached: allowCached);

  Future<CoinData<ShareCoinBalance>> getCurrentWallet({
    bool allowCached = true,
  }) => _read(ShareCoinOperation.wallet, (j, scope) {
    final wallet = ShareCoinBalance.fromJson(j);
    return _owned(wallet, wallet.userId, scope);
  }, allowCached: allowCached);

  Future<CoinData<CoinPage<ShareCoinTransaction>>> getTransactionHistory({
    OfferQuery? query,
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.transactions,
    (j, scope) {
      final page = CoinPage<ShareCoinTransaction>.fromJson(
        j,
        ShareCoinTransaction.fromJson,
        (value) => value.transactionId,
      );
      for (final item in page.items) {
        _owned(item, item.userId, scope);
      }
      return page;
    },
    arguments: (query ?? OfferQuery()).toJson(),
    allowCached: allowCached,
  );

  Future<CoinData<CoinPage<RewardEvent>>> getRewardHistory({
    OfferQuery? query,
  }) => _read(ShareCoinOperation.rewardHistory, (j, scope) {
    final page = CoinPage<RewardEvent>.fromJson(
      j,
      RewardEvent.fromJson,
      (value) => value.eventId,
    );
    for (final item in page.items) {
      _owned(item, item.userId, scope);
    }
    return page;
  }, arguments: (query ?? OfferQuery()).toJson());

  Future<CoinData<CoinPage<Offer>>> getOffers({
    OfferQuery? query,
    bool allowCached = true,
    int? minimumReward,
    int? maximumReward,
  }) => _read(
    ShareCoinOperation.offers,
    (j, scope) =>
        CoinPage<Offer>.fromJson(j, Offer.fromJson, (value) => value.offerId),
    arguments: _offerArguments(
      query ?? OfferQuery(),
      minimumReward,
      maximumReward,
    ),
    allowCached: allowCached,
  );

  Future<CoinData<Offer>> getOfferStatus(
    String offerId, {
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.offerStatus,
    (j, scope) {
      final offer = Offer.fromJson(j);
      if (offer.offerId != offerId) throw const CoinModelException('offerId');
      return offer;
    },
    arguments: {'offerId': coinId(offerId, 'offerId')},
    allowCached: allowCached,
  );

  Future<CoinData<CoinPage<Promotion>>> getPromotions({OfferQuery? query}) =>
      _read(
        ShareCoinOperation.promotions,
        (j, scope) => CoinPage<Promotion>.fromJson(
          j,
          Promotion.fromJson,
          (value) => value.campaignId,
        ),
        arguments: (query ?? OfferQuery()).toJson(),
      );

  Future<CoinData<AdConfiguration>> getAdConfiguration({
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.adsConfiguration,
    (j, scope) => AdConfiguration.fromJson(j),
    allowCached: allowCached,
  );
  Future<CoinData<DailyRewardConfiguration>> getDailyRewardConfiguration({
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.dailyConfiguration,
    (j, scope) => DailyRewardConfiguration.fromJson(j),
    allowCached: allowCached,
  );
  Future<CoinData<ReferralSummary>> getReferral() =>
      _read(ShareCoinOperation.referral, (j, scope) {
        final referral = ReferralSummary.fromJson(j);
        return _owned(referral, referral.userId, scope);
      });
  Future<CoinServiceState> getServiceStatus() async =>
      (await connectivity.refresh()).shareCoin;

  Future<CoinData<WithdrawalPolicy>> getWithdrawalPolicy({
    bool allowCached = true,
  }) => _read(ShareCoinOperation.withdrawalPolicy, (j, scope) {
    final policy = WithdrawalPolicy.fromJson(j);
    return _owned(policy, policy.userId, scope);
  }, allowCached: allowCached);

  Future<CoinData<CoinPage<WithdrawalRequest>>> getWithdrawalHistory({
    OfferQuery? query,
    bool allowCached = true,
  }) => _read(
    ShareCoinOperation.withdrawals,
    (j, scope) {
      final page = CoinPage<WithdrawalRequest>.fromJson(
        j,
        WithdrawalRequest.fromJson,
        (value) => value.withdrawalId,
      );
      for (final item in page.items) {
        _owned(item, item.userId, scope);
      }
      return page;
    },
    arguments: (query ?? OfferQuery()).toJson(),
    allowCached: allowCached,
  );

  Future<void> _activeAccount(AccountScope scope, int generation) async {
    final user = await getCurrentUser(allowCached: false);
    _current(scope, generation);
    if (!user.data.mayRequestRewards) {
      throw const ShareCoinException(CoinErrorCode.restricted);
    }
  }

  Future<CoinData<T>> _mutate<T extends Object>(
    String logicalKey,
    String fingerprint,
    List<String> aliases,
    String idempotencyKey,
    Future<CoinData<T>> Function(AccountScope, int, void Function())
    operation, {
    bool withdrawal = false,
  }) {
    try {
      final scope = _scope();
      final generation = _generation;
      final previous = _mutations[logicalKey];
      for (final alias in aliases) {
        final owner = _aliases[alias];
        if (owner != null && owner != logicalKey) {
          throw const ShareCoinException(CoinErrorCode.conflict);
        }
      }
      if (previous != null) {
        if (previous.fingerprint != fingerprint) {
          throw const ShareCoinException(CoinErrorCode.conflict);
        }
        final combined = previous.aliases.union(aliases.toSet());
        if (combined.length > 16) {
          throw const ShareCoinException(CoinErrorCode.rateLimited);
        }
        previous.aliases.addAll(aliases);
        for (final alias in aliases) {
          _aliases[alias] = logicalKey;
        }
        return previous.future.then((value) => value as CoinData<T>);
      }
      if (withdrawal &&
          (_withdrawalLock != null || _activeWithdrawalId != null)) {
        throw const ShareCoinException(CoinErrorCode.conflict);
      }
      while (_mutations.length >= mutationLimit) {
        final removable = _mutations.entries
            .where((entry) => entry.value.settled && !entry.value.uncertain)
            .firstOrNull;
        if (removable == null) {
          throw const ShareCoinException(CoinErrorCode.rateLimited);
        }
        _mutations.remove(removable.key);
        for (final alias in removable.value.aliases) {
          _aliases.remove(alias);
        }
      }
      final completion = Completer<CoinData<T>>();
      final record = _CoinMutation(
        fingerprint,
        idempotencyKey,
        completion.future,
      );
      record.aliases.addAll(aliases);
      _mutations[logicalKey] = record;
      for (final alias in aliases) {
        _aliases[alias] = logicalKey;
      }
      if (withdrawal) _withdrawalLock = idempotencyKey;
      var sent = false;
      Future<void>(() async {
        try {
          await _online(scope, generation);
          await _activeAccount(scope, generation);
          final result = await operation(scope, generation, () {
            _current(scope, generation);
            if (_suspended) {
              throw const ShareCoinException(CoinErrorCode.offline);
            }
            sent = true;
            _invalidateWallet(scope);
          });
          _current(scope, generation);
          record.settled = true;
          _invalidateWallet(scope);
          completion.complete(result);
          if (!_closed) notifyListeners();
        } catch (error) {
          record.settled = true;
          record.uncertain =
              sent &&
              (error is! ShareCoinException ||
                  error.outcomeUncertain ||
                  error.code == CoinErrorCode.accountChanged ||
                  error.code == CoinErrorCode.disposed);
          final failure = record.uncertain
              ? const ShareCoinException(CoinErrorCode.uncertain)
              : error;
          if (!sent && identical(_mutations[logicalKey], record)) {
            _mutations.remove(logicalKey);
            for (final alias in record.aliases) {
              _aliases.remove(alias);
            }
          }
          completion.completeError(failure);
        } finally {
          if (sent &&
              !_closed &&
              _backend.scope?.key == scope.key &&
              generation == _generation) {
            _invalidateWallet(scope);
          }
          if (withdrawal &&
              !record.uncertain &&
              _backend.scope?.key == scope.key &&
              generation == _generation &&
              _withdrawalLock == idempotencyKey) {
            _withdrawalLock = null;
          }
        }
      });
      return completion.future;
    } catch (error) {
      return Future<CoinData<T>>.error(error);
    }
  }

  void _invalidateWallet(AccountScope scope) {
    if (_closed || _backend.scope?.key != scope.key) return;
    _walletGeneration += 1;
    _cache.removeWhere((key, value) => key.startsWith('${scope.key}|wallet|'));
    notifyListeners();
  }

  Future<CoinData<RewardEvent>> submitRewardEvent(RewardEvent event) {
    if (event.status != RewardEventStatus.created ||
        event.transactionId != null) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.invalidRequest),
      );
    }
    final signature = event.toJson()
      ..remove('eventId')
      ..remove('idempotencyKey')
      ..remove('occurredAt');
    return _mutate(
      'reward:${event.actionKey}',
      jsonEncode(_canonical(signature)),
      ['rewardId:${event.eventId}', 'key:${event.idempotencyKey}'],
      event.idempotencyKey,
      (scope, generation, sent) async {
        if (event.userId != scope.userId) {
          throw const ShareCoinException(CoinErrorCode.accountChanged);
        }
        sent();
        return _execute(
          scope,
          generation,
          ShareCoinOperation.submitReward,
          event.toJson(),
          (j, owner) {
            final reply = RewardEvent.fromJson(j);
            if (reply.userId != owner.userId ||
                reply.eventId != event.eventId ||
                reply.actionKey != event.actionKey ||
                reply.idempotencyKey != event.idempotencyKey ||
                reply.requestedCoins != event.requestedCoins ||
                reply.status == RewardEventStatus.created ||
                reply.status == RewardEventStatus.submitted) {
              throw const CoinModelException('reward confirmation');
            }
            return reply;
          },
          mutation: true,
        );
      },
    );
  }

  Future<CoinData<RewardEvent>> getRewardEventStatus(String eventId) => _read(
    ShareCoinOperation.rewardStatus,
    (j, scope) {
      final event = RewardEvent.fromJson(j);
      if (event.userId != scope.userId || event.eventId != eventId) {
        throw const CoinModelException('reward identity');
      }
      return event;
    },
    arguments: {'eventId': coinId(eventId, 'eventId')},
    allowCached: false,
  );

  Future<CoinData<OfferStart>> startOffer(
    String offerId, {
    required String idempotencyKey,
  }) {
    coinId(offerId, 'offerId');
    coinId(idempotencyKey, 'idempotencyKey');
    return _mutate(
      'offer:$offerId',
      offerId,
      ['key:$idempotencyKey'],
      idempotencyKey,
      (scope, generation, sent) async {
        final offer = await getOfferStatus(offerId, allowCached: false);
        _current(scope, generation);
        if (!offer.data.availableAt(offer.serverTime)) {
          throw const ShareCoinException(CoinErrorCode.invalidRequest);
        }
        sent();
        return _execute(
          scope,
          generation,
          ShareCoinOperation.startOffer,
          {'offerId': offerId, 'idempotencyKey': idempotencyKey},
          (j, owner) {
            final start = OfferStart.fromJson(j);
            if (start.offerId != offerId ||
                start.userId != owner.userId ||
                start.idempotencyKey != idempotencyKey) {
              throw const CoinModelException('offer start confirmation');
            }
            return start;
          },
          mutation: true,
        );
      },
    );
  }

  Future<CoinData<WithdrawalRequest>> requestWithdrawal(
    WithdrawalIntent intent,
  ) => _mutate(
    'withdrawal:${intent.idempotencyKey}',
    jsonEncode(_canonical(intent.toJson())),
    ['key:${intent.idempotencyKey}'],
    intent.idempotencyKey,
    (scope, generation, sent) async {
      if (intent.userId != scope.userId) {
        throw const ShareCoinException(CoinErrorCode.accountChanged);
      }
      final policy = (await getWithdrawalPolicy(allowCached: false)).data;
      final wallet = (await getCurrentWallet(allowCached: false)).data;
      _current(scope, generation);
      if (intent.coins < policy.minimumCoins) {
        throw const ShareCoinException(CoinErrorCode.minimum);
      }
      if (intent.coins > wallet.available) {
        throw const ShareCoinException(CoinErrorCode.insufficientBalance);
      }
      if (policy.activeRequestIds.isNotEmpty) {
        throw const ShareCoinException(CoinErrorCode.conflict);
      }
      if (policy.version != intent.policyVersion) {
        throw const ShareCoinException(CoinErrorCode.policyChanged);
      }
      final method = policy.methods
          .where((method) => method.method == intent.method)
          .firstOrNull;
      if (method == null ||
          !method.usable ||
          method.destinationReference != intent.destinationReference) {
        throw const ShareCoinException(CoinErrorCode.payoutUnavailable);
      }
      final gross = policy.rate.grossMinor(intent.coins);
      if (method.feeMinor > gross ||
          method.feeMinor != intent.expectedFeeMinor ||
          gross - method.feeMinor != intent.expectedFinalMinor) {
        throw const ShareCoinException(CoinErrorCode.policyChanged);
      }
      sent();
      final response = await _execute(
        scope,
        generation,
        ShareCoinOperation.requestWithdrawal,
        intent.toJson(),
        (j, owner) {
          final request = WithdrawalRequest.fromJson(j);
          if (request.userId != owner.userId ||
              request.idempotencyKey != intent.idempotencyKey ||
              request.requestedCoins != intent.coins ||
              request.method != intent.method ||
              request.maskedDestination != method.maskedDestination ||
              request.feeMinor != intent.expectedFeeMinor ||
              request.finalPayoutMinor != intent.expectedFinalMinor ||
              jsonEncode(request.rate.toJson()) !=
                  jsonEncode(policy.rate.toJson())) {
            throw const CoinModelException('withdrawal confirmation');
          }
          return request;
        },
        mutation: true,
      );
      _rememberWithdrawal(response.data);
      return response;
    },
    withdrawal: true,
  );

  void _rememberWithdrawal(WithdrawalRequest request) {
    final previous = _withdrawalStates[request.withdrawalId];
    if (previous != null &&
        (request.updatedAt.isBefore(previous.updatedAt) ||
            !previous.canTransitionTo(request.status))) {
      throw const CoinModelException('withdrawal status regression');
    }
    _withdrawalStates[request.withdrawalId] = request;
    if (_withdrawalStates.length > 100) {
      _withdrawalStates.remove(_withdrawalStates.keys.first);
    }
    if (request.active) {
      _activeWithdrawalId = request.withdrawalId;
    } else if (_activeWithdrawalId == request.withdrawalId ||
        _withdrawalLock == request.idempotencyKey) {
      _activeWithdrawalId = null;
      _withdrawalLock = null;
    }
  }

  Future<CoinData<WithdrawalRequest>> getWithdrawalStatus(
    String withdrawalId,
  ) async {
    final response = await _read(
      ShareCoinOperation.withdrawalStatus,
      (j, scope) {
        final request = WithdrawalRequest.fromJson(j);
        if (request.withdrawalId != withdrawalId ||
            request.userId != scope.userId) {
          throw const CoinModelException('withdrawal identity');
        }
        return request;
      },
      arguments: {'withdrawalId': coinId(withdrawalId, 'withdrawalId')},
      allowCached: false,
    );
    try {
      _rememberWithdrawal(response.data);
    } on CoinModelException {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    return response;
  }

  Future<CoinData<WithdrawalRequest>> getWithdrawalByKey(
    String idempotencyKey,
  ) async {
    final response = await _read(
      ShareCoinOperation.withdrawalByKey,
      (j, scope) {
        final request = WithdrawalRequest.fromJson(j);
        if (request.userId != scope.userId ||
            request.idempotencyKey != idempotencyKey) {
          throw const CoinModelException('withdrawal key');
        }
        return request;
      },
      arguments: {'idempotencyKey': coinId(idempotencyKey, 'idempotencyKey')},
      allowCached: false,
    );
    try {
      _rememberWithdrawal(response.data);
    } on CoinModelException {
      throw const ShareCoinException(CoinErrorCode.malformed);
    }
    return response;
  }

  Map<String, Object?> _offerArguments(
    OfferQuery query,
    int? minimum,
    int? maximum,
  ) {
    if (minimum != null) coinInt(minimum, 'minimumReward');
    if (maximum != null) coinInt(maximum, 'maximumReward');
    if (minimum != null && maximum != null && minimum > maximum) {
      throw const CoinModelException('reward range');
    }
    final args = query.toJson();
    if (minimum != null) args['minimumReward'] = minimum;
    if (maximum != null) args['maximumReward'] = maximum;
    return args;
  }

  bool get rewardExtensionsAvailable =>
      _backend.configured && _backend is ShareCoinRewardBackend;

  Future<Map<String, dynamic>> _extension(
    ShareCoinRewardOperation operation,
    AccountScope scope,
    Map<String, Object?> arguments,
  ) {
    final backend = _backend;
    if (backend is! ShareCoinRewardBackend) {
      throw const ShareCoinException(CoinErrorCode.notConfigured);
    }
    return backend.executeRewardExtension(
      operation,
      scope,
      Map<String, Object?>.unmodifiable(arguments),
    );
  }

  Future<CoinData<ShareCoinTransaction>> getTransaction(
    String transactionId, {
    bool allowCached = false,
  }) => _read(
    ShareCoinOperation.transactions,
    (j, scope) {
      final transaction = ShareCoinTransaction.fromJson(j);
      if (transaction.transactionId != transactionId) {
        throw const CoinModelException('transactionId');
      }
      return _owned(transaction, transaction.userId, scope);
    },
    arguments: {'transactionId': coinId(transactionId, 'transactionId')},
    allowCached: allowCached,
    request: (scope, args) =>
        _extension(ShareCoinRewardOperation.transaction, scope, args),
  );

  Future<CoinData<RewardSession>> prepareRewardSession(
    CoinSource source,
    String targetId, {
    required String idempotencyKey,
  }) {
    coinId(targetId, 'targetId');
    coinId(idempotencyKey, 'idempotencyKey');
    if (!rewardExtensionsAvailable) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.notConfigured),
      );
    }
    if (!<CoinSource>{
      CoinSource.adReward,
      CoinSource.dailyReward,
      CoinSource.promotionReward,
    }.contains(source)) {
      return Future.error(
        const ShareCoinException(CoinErrorCode.invalidRequest),
      );
    }
    final args = <String, Object?>{
      'source': source.name,
      'targetId': targetId,
      'idempotencyKey': idempotencyKey,
    };
    return _mutate(
      'reward-session:$idempotencyKey',
      jsonEncode(args),
      ['session-key:$idempotencyKey'],
      idempotencyKey,
      (scope, generation, sent) async {
        sent();
        return _execute(
          scope,
          generation,
          ShareCoinOperation.submitReward,
          args,
          (j, owner) {
            final session = RewardSession.fromJson(j);
            if (session.userId != owner.userId ||
                session.source != source ||
                session.targetId != targetId ||
                session.requestKey != idempotencyKey) {
              throw const CoinModelException('reward session identity');
            }
            return session;
          },
          mutation: true,
          request: () =>
              _extension(ShareCoinRewardOperation.prepareReward, scope, args),
        );
      },
    );
  }

  Future<CoinData<RewardSession>> getRewardSessionStatus({
    String? sessionId,
    String? requestKey,
  }) {
    if ((sessionId == null) == (requestKey == null)) {
      throw const CoinModelException('one session reference required');
    }
    final args = <String, Object?>{};
    if (sessionId != null) args['sessionId'] = coinId(sessionId, 'sessionId');
    if (requestKey != null) {
      args['requestKey'] = coinId(requestKey, 'requestKey');
    }
    return _read(
      ShareCoinOperation.rewardStatus,
      (j, scope) {
        final session = RewardSession.fromJson(j);
        if (session.userId != scope.userId ||
            sessionId != null && session.sessionId != sessionId ||
            requestKey != null && session.requestKey != requestKey) {
          throw const CoinModelException('reward session identity');
        }
        return session;
      },
      arguments: args,
      allowCached: false,
      request: (scope, args) =>
          _extension(ShareCoinRewardOperation.sessionStatus, scope, args),
    );
  }

  Future<CoinData<OfferLaunchGrant>> getOfferLaunch(
    OfferStart start,
    OfferPlatform platform,
  ) => _read(
    ShareCoinOperation.offerStatus,
    (j, scope) {
      final grant = OfferLaunchGrant.fromJson(j);
      if (grant.userId != scope.userId ||
          start.userId != scope.userId ||
          grant.startId != start.startId ||
          grant.offerId != start.offerId ||
          grant.platform != platform) {
        throw const CoinModelException('offer launch grant');
      }
      return grant;
    },
    arguments: {'startId': start.startId, 'platform': platform.name},
    allowCached: false,
    request: (scope, args) =>
        _extension(ShareCoinRewardOperation.offerLaunch, scope, args),
  );

  void suspend() {
    if (_closed) return;
    _suspended = true;
    connectivity.suspend();
  }

  void resume() {
    if (_closed) return;
    _suspended = false;
    connectivity.resume();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation += 1;
    unawaited(_accountSubscription.cancel());
    _cache.clear();
    _reads.clear();
    _mutations.clear();
    _aliases.clear();
    if (_ownsConnectivity) connectivity.dispose();
    super.dispose();
  }
}
```

## File 25 — `lib/screens/share_coin_home_screen.dart` — UPDATED

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/share_coin_models.dart';
import '../models/user_models.dart';
import '../services/connectivity_service.dart';
import '../services/share_coin_service.dart';
import '../services/offerwall_service.dart';
import 'offerwall_screen.dart';
import 'reward_center_screen.dart';

enum ShareCoinFileAction { send, receive, saved, history }

class ShareCoinHomeScreen extends StatefulWidget {
  const ShareCoinHomeScreen({
    super.key,
    this.service,
    this.onFileAction,
    this.offerPolicy,
    this.adFactory = createUnavailableRewardedAdAdapter,
    this.linkLauncher = launchRewardLink,
  });
  final ShareCoinService? service;
  final ValueChanged<ShareCoinFileAction>? onFileAction;
  final OfferResourcePolicy? offerPolicy;
  final RewardedAdAdapter Function() adFactory;
  final RewardLinkLauncher linkLauncher;
  @override
  State<ShareCoinHomeScreen> createState() => _ShareCoinHomeScreenState();
}

class _ShareCoinHomeScreenState extends State<ShareCoinHomeScreen>
    with WidgetsBindingObserver {
  late final ShareCoinService _service;
  late final bool _ownsService;
  CoinData<ShareCoinBalance>? _wallet;
  CoinData<ShareCoinUser>? _user;
  String? _scopeKey;
  String? _notice;
  String? _busyAction;
  bool _loading = false;
  bool _closed = false;
  bool _navigating = false;
  int _generation = 0;
  bool get _canUpdate => mounted && !_closed;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? ShareCoinService();
    _scopeKey = _service.accountKey;
    _service.addListener(_serviceChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _serviceChanged() {
    if (!_canUpdate) return;
    final next = _service.accountKey;
    if (next != _scopeKey) {
      _generation += 1;
      setState(() {
        _scopeKey = next;
        _wallet = null;
        _user = null;
        _busyAction = null;
        _loading = false;
        _notice = 'Account changed. Refresh to load this account.';
      });
    } else if (_service.cachedWallet == null && _wallet != null) {
      setState(() => _wallet = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generation += 1;
      _service.suspend();
      if (_canUpdate) {
        setState(() {
          _loading = false;
          _busyAction = null;
          _notice =
              'ShareCoin refresh paused. File sharing has its own lifecycle.';
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _service.resume();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_serviceChanged);
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || _busyAction != null) return;
    final generation = ++_generation;
    final scope = _service.accountKey;
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      await _service.connectivity.refresh();
      if (!_service.backendConfigured) {
        if (_canUpdate && generation == _generation) {
          setState(
            () => _notice = 'Backend and sign-in integration are not configured. No real funds are shown.',
          );
        }
        return;
      }
      if (!_service.hasAccount) {
        if (_canUpdate && generation == _generation) {
          setState(
            () => _notice = 'Account setup required. No authentication provider is integrated in this foundation.',
          );
        }
        return;
      }
      final user = await _service.getCurrentUser();
      final wallet = await _service.getCurrentWallet();
      if (_canUpdate &&
          generation == _generation &&
          scope == _service.accountKey) {
        setState(() {
          _user = user;
          _wallet = wallet;
          _scopeKey = scope;
        });
      }
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        setState(() {
          _wallet = _service.cachedWallet;
          _notice = _errorText(error);
        });
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _errorText(Object error) => error is ShareCoinException
      ? error.message
      : 'ShareCoin could not load this information. No local reward or payout was created.';
  String _time(DateTime date) => date.toLocal().toString().split('.').first;
  String _coins(int coins) => coins.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );

  void _fileAction(ShareCoinFileAction action) {
    final callback = widget.onFileAction;
    if (callback != null) {
      callback(action);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(action);
    }
  }

  Future<void> _info(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _details(
    String title,
    Future<List<Widget>> Function() load,
  ) async {
    if (_busyAction != null || _loading) return;
    final scope = _service.accountKey;
    final generation = ++_generation;
    setState(() => _busyAction = title);
    try {
      final rows = await load();
      if (!mounted ||
          _closed ||
          generation != _generation ||
          scope != _service.accountKey) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: _service,
          builder: (context, child) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: scope != _service.accountKey
                  ? const Text('Account changed. Close this view and refresh.')
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                      ),
                      child: ListView(shrinkWrap: true, children: rows),
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        await _info(title, _errorText(error));
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _busyAction = null);
      }
    }
  }

  Widget _origin<T>(CoinData<T> data) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      '${data.cached ? 'Cached data' : 'Backend response'} · ${_time(data.serverTime)}',
      style: const TextStyle(fontSize: 12),
    ),
  );

  Future<void> _openOfferwall() async {
    if (_navigating || !_canUpdate) return;
    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => OfferwallScreen(
            service: _service,
            policy: widget.offerPolicy,
            launcher: widget.linkLauncher,
            onCatalogInfo: _offers,
          ),
        ),
      );
    } finally {
      _navigating = false;
      if (_canUpdate) unawaited(_refresh());
    }
  }

  Future<void> _openRewardCenter(
    RewardCenterMode mode,
    VoidCallback configuration,
  ) async {
    if (_navigating || !_canUpdate) return;
    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => RewardCenterScreen(
            service: _service,
            mode: mode,
            policy: widget.offerPolicy,
            adFactory: widget.adFactory,
            launcher: widget.linkLauncher,
            onConfiguration: configuration,
          ),
        ),
      );
    } finally {
      _navigating = false;
      if (_canUpdate) unawaited(_refresh());
    }
  }

  Future<void> _ads() => _details('Watch Ads', () async {
    final data = await _service.getAdConfiguration();
    return <Widget>[
      _origin(data),
      Text('Provider: ${data.data.provider ?? 'Not configured'}'),
      Text(
        'Rewarded ads: ${data.data.rewardedEnabled && !data.data.premium ? 'Enabled in backend configuration' : 'Disabled'}',
      ),
      Text(
        'Cooldown: ${data.data.cooldownSeconds}s · Daily limit: ${data.data.dailyLimit}',
      ),
      Text('Premium/no-ads: ${data.data.premium ? 'Yes' : 'No'}'),
      const SizedBox(height: 12),
      const Text(
        'No ad SDK is bundled. A configured provider completion is only an event claim; the backend must verify it before crediting ShareCoin.',
      ),
    ];
  });

  Future<void> _offers() => _details('Offers', () async {
    final data = await _service.getOffers(query: OfferQuery(pageSize: 20));
    return <Widget>[
      _origin(data),
      const Text(
        'Catalog foundation. Starting/installing an app is not proof of earning a reward.',
      ),
      if (data.data.items.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('No offers returned for this account.'),
        ),
      for (final offer in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.apps_rounded),
          title: Text(offer.title),
          subtitle: Text(
            '${offer.publisher} · ${offer.category.name}\nPotential reward: ${offer.rewardCoins} ShareCoin · ${offer.status.name}',
          ),
        ),
      if (data.data.info.hasNext)
        Text(
          'Showing ${data.data.items.length} of ${data.data.info.total}. The service supports paginated queries; this dashboard is a bounded catalog preview.',
        ),
    ];
  });

  Future<void> _promotions() => _details('Promotions', () async {
    final data = await _service.getPromotions(query: OfferQuery(pageSize: 20));
    return <Widget>[
      _origin(data),
      const Text('Opening a campaign never credits coins in this client.'),
      if (data.data.items.isEmpty) const Text('No promotions returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined),
          title: Text(item.title),
          subtitle: Text(
            '${item.advertiser}\nPotential reward: ${item.rewardCoins} ShareCoin · ${item.status.name}\nEnds ${_time(item.endsAt)}',
          ),
        ),
    ];
  });

  Future<void> _daily() => _details('Daily Reward', () async {
    final data = await _service.getDailyRewardConfiguration();
    return <Widget>[
      _origin(data),
      Text('Backend streak day: ${data.data.streakDay}'),
      Text(
        'Backend eligibility: ${data.data.eligible ? 'Eligible according to this response' : 'Not eligible'}',
      ),
      for (var index = 0; index < data.data.dayRewards.length; index += 1)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Day ${index + 1}'),
          trailing: Text('${data.data.dayRewards[index]} ShareCoin'),
        ),
      Text('Next eligible: ${_time(data.data.nextEligibleAt)}'),
      const SizedBox(height: 12),
      const Text(
        'This is the server-configured policy view, not a local claim button. Device date does not award money.',
      ),
    ];
  });

  Future<void> _referral() => _details('Referral', () async {
    final data = await _service.getReferral();
    return <Widget>[
      _origin(data),
      SelectableText(
        data.data.referralCode,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      Text(
        'Invited: ${data.data.invitedCount} · Pending: ${data.data.pendingCount} · Qualified: ${data.data.qualifiedCount}',
      ),
      Text('Backend referral earnings: ${data.data.earnedCoins} ShareCoin'),
      Text('Status: ${data.data.status.name}'),
      if (data.data.referralUrl != null)
        SelectableText(data.data.referralUrl.toString()),
      const SizedBox(height: 12),
      const Text(
        'Referrals require backend qualification and anti-abuse checks. Multiple local accounts do not earn rewards.',
      ),
      TextButton(
        onPressed: () async {
          if (data.accountKey == _service.accountKey) {
            await Clipboard.setData(
              ClipboardData(text: data.data.referralCode),
            );
          }
        },
        child: const Text('Copy referral code'),
      ),
    ];
  });

  Future<void> _transactions() => _details('Transactions', () async {
    final data = await _service.getTransactionHistory(
      query: OfferQuery(pageSize: 30),
    );
    return <Widget>[
      _origin(data),
      if (data.data.items.isEmpty) const Text('No transactions returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          isThreeLine: true,
          title: Text(item.signedAmount),
          subtitle: Text(
            '${item.source.name} · ${item.status.name}\n${_time(item.createdAt)} · ${item.transactionId}\n${item.description}',
          ),
        ),
      if (data.data.info.hasNext)
        const Text(
          'More transactions are available through the paginated service. Rejected and reversed entries are not hidden.',
        ),
    ];
  });

  Future<void> _withdrawals() => _details('Withdrawal History', () async {
    final data = await _service.getWithdrawalHistory(
      query: OfferQuery(pageSize: 20),
    );
    return <Widget>[
      _origin(data),
      if (data.data.items.isEmpty)
        const Text('No withdrawal records returned.'),
      for (final item in data.data.items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${item.requestedCoins} ShareCoin · ${item.status.name}'),
          subtitle: Text(
            '${item.method.name} · ${item.maskedDestination}\n${item.rate.formatMinor(item.finalPayoutMinor)} · ${item.withdrawalId}\n${item.rejectionReason ?? 'Status provided by the backend'}',
          ),
        ),
    ];
  });

  Future<void> _withdraw() async {
    if (_busyAction != null || _loading) return;
    if (!_service.backendConfigured ||
        !_service.hasAccount ||
        !_service.connectivity.value.canRequestRewards) {
      await _info(
        'Withdrawals unavailable',
        'A backend-authenticated account, reachable ShareCoin service, fresh balance, payout policy and connected saved destination are required. No submission was made. bKash, Nagad, Rocket, PayPal and Bank are configuration options only, not connected providers.',
      );
      return;
    }
    final generation = ++_generation;
    final scope = _service.accountKey;
    setState(() => _busyAction = 'Withdraw');
    try {
      final user = await _service.getCurrentUser(allowCached: false);
      if (!user.data.mayRequestRewards) {
        throw const ShareCoinException(CoinErrorCode.restricted);
      }
      final wallet = await _service.getCurrentWallet(allowCached: false);
      final policy = await _service.getWithdrawalPolicy(allowCached: false);
      if (!mounted ||
          _closed ||
          generation != _generation ||
          scope != _service.accountKey) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _WithdrawalDialog(
          service: _service,
          wallet: wallet,
          policy: policy,
        ),
      );
    } catch (error) {
      if (_canUpdate && generation == _generation) {
        await _info('Withdraw', _errorText(error));
      }
    } finally {
      if (_canUpdate && generation == _generation) {
        setState(() => _busyAction = null);
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('share-coin-home'),
      appBar: AppBar(
        title: const Text('ShareCoin'),
        toolbarHeight: 70,
        actions: <Widget>[
          IconButton(
            key: const ValueKey('refresh-share-coin'),
            onPressed: _loading || _busyAction != null ? null : _refresh,
            tooltip: 'Refresh ShareCoin status',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  _balance(theme),
                  if (_loading || _busyAction != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_notice != null) _CoinNotice(message: _notice!),
                  const SizedBox(height: 22),
                  _section('Earn', 'Actions create claims, not local money.'),
                  _grid(<Widget>[
                    _tile(
                      'Watch Ads',
                      Icons.play_circle_outline_rounded,
                      () => _openRewardCenter(RewardCenterMode.ad, _ads),
                      'Provider / backend required',
                      key: 'coin-watch-ads',
                    ),
                    _tile(
                      'Offers',
                      Icons.apps_rounded,
                      _openOfferwall,
                      'Paginated Offerwall',
                      key: 'coin-offers',
                    ),
                    _tile(
                      'Promotions',
                      Icons.campaign_outlined,
                      () => _openRewardCenter(
                        RewardCenterMode.promotions,
                        _promotions,
                      ),
                      'Campaign verification',
                      key: 'coin-promotions',
                    ),
                    _tile(
                      'Daily Reward',
                      Icons.calendar_today_outlined,
                      () => _openRewardCenter(RewardCenterMode.daily, _daily),
                      'Server eligibility',
                      key: 'coin-daily',
                    ),
                    _tile(
                      'Referral',
                      Icons.people_outline_rounded,
                      _referral,
                      'Qualified invites',
                      key: 'coin-referral',
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'Wallet',
                    'Only backend-confirmed records are displayed.',
                  ),
                  _grid(<Widget>[
                    _tile(
                      'Transactions',
                      Icons.receipt_long_outlined,
                      () => _openRewardCenter(
                        RewardCenterMode.transactions,
                        _transactions,
                      ),
                      'Credits, debits, reversals',
                      key: 'coin-transactions',
                    ),
                    _tile(
                      'Withdraw',
                      Icons.account_balance_outlined,
                      _withdraw,
                      'Backend/provider required',
                      key: 'coin-withdraw',
                    ),
                    _tile(
                      'Withdrawal History',
                      Icons.history_rounded,
                      () => _openRewardCenter(
                        RewardCenterMode.withdrawals,
                        _withdrawals,
                      ),
                      'Server payout status',
                      key: 'coin-withdrawal-history',
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'File Sharing',
                    'Internet rewards never block your nearby files.',
                  ),
                  _grid(<Widget>[
                    _tile(
                      'Send Files',
                      Icons.upload_rounded,
                      () => _fileAction(ShareCoinFileAction.send),
                      'Original file flow',
                      key: 'coin-send-files',
                      local: true,
                    ),
                    _tile(
                      'Receive Files',
                      Icons.download_rounded,
                      () => _fileAction(ShareCoinFileAction.receive),
                      'QR or manual pairing',
                      key: 'coin-receive-files',
                      local: true,
                    ),
                    _tile(
                      'Saved Files',
                      Icons.folder_copy_outlined,
                      () => _fileAction(ShareCoinFileAction.saved),
                      'Your received copies',
                      key: 'coin-saved-files',
                      local: true,
                    ),
                    _tile(
                      'History',
                      Icons.fact_check_outlined,
                      () => _fileAction(ShareCoinFileAction.history),
                      'Existing history & SHA-256',
                      key: 'coin-file-history',
                      local: true,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _section(
                    'Status',
                    'Local interfaces, internet and backend are separate.',
                  ),
                  ValueListenableBuilder<ConnectivitySnapshot>(
                    valueListenable: _service.connectivity,
                    builder: (context, status, child) => Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Internet: ${status.internetLabel}',
                            key: const ValueKey('coin-internet-status'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Wi-Fi/local network: ${status.localLabel}',
                            key: const ValueKey('coin-local-status'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'ShareCoin service: ${status.serviceLabel}',
                            key: const ValueKey('coin-service-status'),
                          ),
                          if (status.stale)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('Status is stale or checking.'),
                            ),
                          const SizedBox(height: 12),
                          const Text(
                            'An IPv4 interface does not prove Wi-Fi type or peer reachability. No public internet probe is configured by default.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Foundation only. No ad attribution, login provider, advertiser payout or cash withdrawal provider is connected by this build. '
                    'ShareCoin is not locally redeemable money. File sharing keeps its existing TLS and approval rules.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _balance(ThemeData theme) {
    final wallet = _wallet;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF164D3C),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.toll_outlined, color: Color(0xFFD5F391)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SHAREBONDHU REWARDS',
                  style: TextStyle(
                    color: Color(0xFFD5F391),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'ShareCoin Balance',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            wallet == null
                ? 'Wallet unavailable'
                : '${_coins(wallet.data.available)} ShareCoin',
            key: const ValueKey('share-coin-balance'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (wallet == null)
            Text(
              !_service.hasAccount
                  ? 'Account setup required. A backend-confirmed wallet is needed before any funds can be shown.'
                  : 'Connect to the ShareCoin service and refresh to confirm the current balance.',
              style: TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Pending: ${_coins(wallet.data.pending)} ShareCoin',
                  style: const TextStyle(color: Color(0xFFE0EDE5)),
                ),
                const SizedBox(height: 8),
                Text(
                  '${wallet.cached ? 'CACHED · not a live spendable-balance check' : 'Backend response'}\nLast updated: ${_time(wallet.data.updatedAt)}',
                  style: const TextStyle(color: Color(0xFFE0EDE5), height: 1.5),
                ),
              ],
            ),
          if (_user != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${_user!.data.displayName} · ${_user!.data.status.name}',
                style: const TextStyle(color: Color(0xFFD5F391)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _grid(List<Widget> tiles) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560
          ? 3
          : constraints.maxWidth >= 340 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tiles
            .map((tile) => SizedBox(width: width, child: tile))
            .toList(),
      );
    },
  );

  Widget _tile(
    String title,
    IconData icon,
    VoidCallback action,
    String description, {
    required String key,
    bool local = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(18),
        onTap: local || !_loading && _busyAction == null ? action : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colors.primary, size: 26),
              const SizedBox(height: 13),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinNotice extends StatelessWidget {
  const _CoinNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(message),
  );
}

class _WithdrawalDialog extends StatefulWidget {
  const _WithdrawalDialog({
    required this.service,
    required this.wallet,
    required this.policy,
  });
  final ShareCoinService service;
  final CoinData<ShareCoinBalance> wallet;
  final CoinData<WithdrawalPolicy> policy;
  @override
  State<_WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<_WithdrawalDialog> {
  final TextEditingController _amount = TextEditingController();
  PayoutMethodConfig? _method;
  String _idempotencyKey = newCoinRequestId();
  String? _error;
  bool _sending = false;
  bool _uncertain = false;
  WithdrawalRequest? _result;
  bool get _ownerMatches =>
      widget.wallet.accountKey == widget.service.accountKey;

  @override
  void initState() {
    super.initState();
    _method = widget.policy.data.methods
        .where((method) => method.usable)
        .firstOrNull;
    _amount.text = widget.policy.data.minimumCoins.toString();
    widget.service.addListener(_update);
    widget.service.connectivity.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_update);
    widget.service.connectivity.removeListener(_update);
    _amount.dispose();
    super.dispose();
  }

  int? get _coins {
    try {
      return coinInt(int.tryParse(_amount.text.trim()), 'coins', min: 1);
    } catch (_) {
      return null;
    }
  }

  int? get _finalMinor {
    final coins = _coins;
    final method = _method;
    if (coins == null || method == null) return null;
    try {
      final value = widget.policy.data.rate.grossMinor(coins) - method.feeMinor;
      return value >= 0 ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _edited() {
    if (!_sending && !_uncertain && _result == null) {
      setState(() {
        _idempotencyKey = newCoinRequestId();
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    final coins = _coins;
    final method = _method;
    final payout = _finalMinor;
    if (_sending ||
        _uncertain ||
        _result != null ||
        !_ownerMatches ||
        !widget.service.connectivity.value.canRequestRewards) {
      return;
    }
    if (coins == null || method == null || payout == null) {
      setState(
        () => _error = 'Enter a valid whole-coin amount and choose a connected destination.',
      );
      return;
    }
    if (coins < widget.policy.data.minimumCoins) {
      setState(() => _error = 'Amount is below the withdrawal minimum.');
      return;
    }
    if (coins > widget.wallet.data.available) {
      setState(() => _error = 'Amount exceeds the displayed backend balance.');
      return;
    }
    setState(() => _sending = true);
    try {
      final response = await widget.service.requestWithdrawal(
        WithdrawalIntent(
          userId: widget.wallet.data.userId,
          coins: coins,
          method: method.method,
          destinationReference: method.destinationReference!,
          policyVersion: widget.policy.data.version,
          expectedFeeMinor: method.feeMinor,
          expectedFinalMinor: payout,
          idempotencyKey: _idempotencyKey,
        ),
      );
      if (mounted && _ownerMatches) setState(() => _result = response.data);
    } catch (error) {
      if (mounted && _ownerMatches) {
        setState(() {
          _error = error is ShareCoinException
              ? error.message
              : 'The request could not be confirmed.';
          _uncertain = error is! ShareCoinException || error.outcomeUncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkRequest() async {
    if (_sending || !_uncertain || !_ownerMatches) return;
    setState(() => _sending = true);
    try {
      final result = await widget.service.getWithdrawalByKey(_idempotencyKey);
      if (mounted && _ownerMatches) {
        setState(() {
          _result = result.data;
          _uncertain = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && _ownerMatches) {
        setState(
          () => _error = error is ShareCoinException
              ? error.message
              : 'The request status is still unknown.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy.data;
    final method = _method;
    final payout = _finalMinor;
    final online = widget.service.connectivity.value.canRequestRewards;
    return AlertDialog(
      title: const Text('Withdrawal request'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: !_ownerMatches
              ? const Text('Account changed. Close this form and refresh.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Backend balance: ${widget.wallet.data.available} ShareCoin',
                    ),
                    Text('Minimum: ${policy.minimumCoins} ShareCoin'),
                    Text(
                      'Rate: ${policy.rate.coinUnits} ShareCoin = ${policy.rate.formatMinor(policy.rate.minorUnits)}',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('coin-withdraw-amount'),
                      controller: _amount,
                      enabled: !_sending && !_uncertain && _result == null,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _edited(),
                      decoration: const InputDecoration(
                        labelText: 'Requested ShareCoin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (policy.methods.isNotEmpty)
                      DropdownButtonFormField<PayoutMethod>(
                        initialValue: method?.method,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Payout method',
                          border: OutlineInputBorder(),
                        ),
                        items: policy.methods
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.method,
                                enabled: entry.usable,
                                child: Text(
                                  '${entry.method.name}${entry.usable ? '' : ' · not connected'}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sending || _uncertain || _result != null
                            ? null
                            : (value) {
                                setState(
                                  () => _method = policy.methods
                                      .where((entry) => entry.method == value)
                                      .firstOrNull,
                                );
                                _edited();
                              },
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Saved destination: ${method?.maskedDestination ?? 'Not configured'}',
                    ),
                    Text(
                      'Processing fee: ${method == null ? 'Unavailable' : policy.rate.formatMinor(method.feeMinor)}',
                    ),
                    Text(
                      'Estimated final payout: ${payout == null ? 'Unavailable' : policy.rate.formatMinor(payout)}',
                    ),
                    if (policy.activeRequestIds.isNotEmpty)
                      const Text(
                        'Another withdrawal is active. Submission is disabled.',
                      ),
                    if (!online)
                      const Text(
                        'Service unavailable. No offline withdrawal submission.',
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Submission requests backend validation; it is not proof of payout. The server must recheck the balance, fees, policy and destination.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!),
                      ),
                    if (_uncertain)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SelectableText(
                          'Check backend withdrawal history using request key: $_idempotencyKey. Do not create another request blindly.',
                        ),
                      ),
                    if (_result != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Backend status: ${_result!.status.name}\nReference: ${_result!.withdrawalId}\nBalance must be refreshed from the backend.',
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_uncertain)
          OutlinedButton(
            key: const ValueKey('check-coin-withdrawal-status'),
            onPressed: _sending || !_ownerMatches || !online
                ? null
                : _checkRequest,
            child: const Text('Check request status'),
          ),
        if (_result == null)
          FilledButton(
            key: const ValueKey('submit-coin-withdrawal'),
            onPressed:
                !_ownerMatches ||
                    _sending ||
                    _uncertain ||
                    !online ||
                    method == null ||
                    policy.activeRequestIds.isNotEmpty
                ? null
                : _submit,
            child: Text(_sending ? 'Submitting request' : 'Request withdrawal'),
          ),
      ],
    );
  }
}
```

## Tool-managed dependency/native support — complete files

### `pubspec.lock` — REGENERATED

```yaml
# Generated by pub
# See https://dart.dev/tools/pub/glossary#lockfile
packages:
  android_file_picker:
    dependency: transitive
    description:
      name: android_file_picker
      sha256: "0d84bb91fb78af33756107f00cf71ee084474169d481b882b335c3006077a913"
      url: "https://pub.dev"
    source: hosted
    version: "1.1.0"
  archive:
    dependency: transitive
    description:
      name: archive
      sha256: ace891da0862b0e4cabbb064ee3fd87b2728b898949fdb366d83fe98342c9f19
      url: "https://pub.dev"
    source: hosted
    version: "4.2.0"
  args:
    dependency: transitive
    description:
      name: args
      sha256: d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04
      url: "https://pub.dev"
    source: hosted
    version: "2.7.0"
  async:
    dependency: transitive
    description:
      name: async
      sha256: e2eb0491ba5ddb6177742d2da23904574082139b07c1e33b8503b9f46f3e1a37
      url: "https://pub.dev"
    source: hosted
    version: "2.13.1"
  basic_utils:
    dependency: "direct main"
    description:
      name: basic_utils
      sha256: "548047bef0b3b697be19fa62f46de54d99c9019a69fb7db92c69e19d87f633c7"
      url: "https://pub.dev"
    source: hosted
    version: "5.8.2"
  boolean_selector:
    dependency: transitive
    description:
      name: boolean_selector
      sha256: "8aab1771e1243a5063b8b0ff68042d67334e3feab9e95b9490f9a6ebf73b42ea"
      url: "https://pub.dev"
    source: hosted
    version: "2.1.2"
  characters:
    dependency: transitive
    description:
      name: characters
      sha256: faf38497bda5ead2a8c7615f4f7939df04333478bf32e4173fcb06d428b5716b
      url: "https://pub.dev"
    source: hosted
    version: "1.4.1"
  clock:
    dependency: transitive
    description:
      name: clock
      sha256: e51d50bca3217c9a9fa2b41a30e4a38971133f5f9ec7a3d57bae095007f1d28e
      url: "https://pub.dev"
    source: hosted
    version: "1.1.3"
  code_assets:
    dependency: transitive
    description:
      name: code_assets
      sha256: bf394f466ba9205f1812a0433b392d6af280f155f56651eda7c18cc32ed493b8
      url: "https://pub.dev"
    source: hosted
    version: "1.2.1"
  collection:
    dependency: transitive
    description:
      name: collection
      sha256: "2f5709ae4d3d59dd8f7cd309b4e023046b57d8a6c82130785d2b0e5868084e76"
      url: "https://pub.dev"
    source: hosted
    version: "1.19.1"
  convert:
    dependency: transitive
    description:
      name: convert
      sha256: b30acd5944035672bc15c6b7a8b47d773e41e2f17de064350988c5d02adb1c68
      url: "https://pub.dev"
    source: hosted
    version: "3.1.2"
  cross_file:
    dependency: transitive
    description:
      name: cross_file
      sha256: f141ea4f277af142a0356955707f6556f37b03947d39d55585981a06ca437bd6
      url: "https://pub.dev"
    source: hosted
    version: "0.3.5+5"
  crypto:
    dependency: "direct main"
    description:
      name: crypto
      sha256: c8ea0233063ba03258fbcf2ca4d6dadfefe14f02fab57702265467a19f27fadf
      url: "https://pub.dev"
    source: hosted
    version: "3.0.7"
  dbus:
    dependency: transitive
    description:
      name: dbus
      sha256: a48d5da28e89bd02196e80d81ed8d7954923d00a0f4a68cc20b575038f023383
      url: "https://pub.dev"
    source: hosted
    version: "0.7.15"
  fake_async:
    dependency: transitive
    description:
      name: fake_async
      sha256: "5368f224a74523e8d2e7399ea1638b37aecfca824a3cc4dfdf77bf1fa905ac44"
      url: "https://pub.dev"
    source: hosted
    version: "1.3.3"
  ffi:
    dependency: transitive
    description:
      name: ffi
      sha256: "6d7fd89431262d8f3125e81b50d3847a091d846eafcd4fdb88dd06f36d705a45"
      url: "https://pub.dev"
    source: hosted
    version: "2.2.0"
  ffi_leak_tracker:
    dependency: transitive
    description:
      name: ffi_leak_tracker
      sha256: "4093d4ef9ca06ffe2786e73bfb25e22aa92112b9bb4ec941f11e3e6b61489a97"
      url: "https://pub.dev"
    source: hosted
    version: "0.1.2"
  file:
    dependency: transitive
    description:
      name: file
      sha256: a3b4f84adafef897088c160faf7dfffb7696046cb13ae90b508c2cbc95d3b8d4
      url: "https://pub.dev"
    source: hosted
    version: "7.0.1"
  file_picker:
    dependency: "direct main"
    description:
      name: file_picker
      sha256: "0631f51bbc2e1184bdc9e79384db158dc7830e15b3001feeca700e86563f4d24"
      url: "https://pub.dev"
    source: hosted
    version: "12.2.0"
  file_picker_darwin:
    dependency: transitive
    description:
      name: file_picker_darwin
      sha256: "5c32c9400f5c8976c9dd7aa34693c7d2f0c853c28704a1c1409029cb760f5251"
      url: "https://pub.dev"
    source: hosted
    version: "1.1.0"
  file_picker_linux:
    dependency: transitive
    description:
      name: file_picker_linux
      sha256: bd52ff1e0048f29df95f913c55ad2991c72791d93e6c42241912c4bdee946cb9
      url: "https://pub.dev"
    source: hosted
    version: "1.1.0"
  file_picker_platform_interface:
    dependency: transitive
    description:
      name: file_picker_platform_interface
      sha256: d35d8cb68446fae921335bb61501d66cb2469d74c8f3103b8c6ccdbe3fe5afd8
      url: "https://pub.dev"
    source: hosted
    version: "3.3.0"
  file_picker_web:
    dependency: transitive
    description:
      name: file_picker_web
      sha256: "935560a9d29fa6f006f2855addebb88e88d438e13627d4cc24187033c106f227"
      url: "https://pub.dev"
    source: hosted
    version: "3.1.0"
  fixnum:
    dependency: transitive
    description:
      name: fixnum
      sha256: b6dc7065e46c974bc7c5f143080a6764ec7a4be6da1285ececdc37be96de53be
      url: "https://pub.dev"
    source: hosted
    version: "1.1.1"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
  flutter_lints:
    dependency: "direct dev"
    description:
      name: flutter_lints
      sha256: "3105dc8492f6183fb076ccf1f351ac3d60564bff92e20bfc4af9cc1651f4e7e1"
      url: "https://pub.dev"
    source: hosted
    version: "6.0.0"
  flutter_test:
    dependency: "direct dev"
    description: flutter
    source: sdk
    version: "0.0.0"
  flutter_web_plugins:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.0"
  hooks:
    dependency: transitive
    description:
      name: hooks
      sha256: "9a62a50b50b769a737bc0a8ff381f333529df3ab746b2f6b02e83760231455ba"
      url: "https://pub.dev"
    source: hosted
    version: "2.0.2"
  http:
    dependency: transitive
    description:
      name: http
      sha256: "87721a4a50b19c7f1d49001e51409bddc46303966ce89a65af4f4e6004896412"
      url: "https://pub.dev"
    source: hosted
    version: "1.6.0"
  http_parser:
    dependency: transitive
    description:
      name: http_parser
      sha256: "178d74305e7866013777bab2c3d8726205dc5a4dd935297175b19a23a2e66571"
      url: "https://pub.dev"
    source: hosted
    version: "4.1.2"
  jni:
    dependency: transitive
    description:
      name: jni
      sha256: f038e58b4dc2c9037f50e233175086337e0b305e356d28211bf55f21c504cbd3
      url: "https://pub.dev"
    source: hosted
    version: "1.0.3"
  jni_flutter:
    dependency: transitive
    description:
      name: jni_flutter
      sha256: b2310cdd4c18c65c081ab141a41efa94aa26c65431803703ece51996f174f351
      url: "https://pub.dev"
    source: hosted
    version: "1.0.3"
  jni_util:
    dependency: transitive
    description:
      name: jni_util
      sha256: "1ba86da04a5f2bf18fde2edb235587e70c5b0fc5bd4ba955f46b00942c3fc35f"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  json_annotation:
    dependency: transitive
    description:
      name: json_annotation
      sha256: "2a743920d81b7910627f68ee2c9ac1fc0bfee32b9fc3403587d7c6791ca12f80"
      url: "https://pub.dev"
    source: hosted
    version: "4.12.0"
  leak_tracker:
    dependency: transitive
    description:
      name: leak_tracker
      sha256: "33e2e26bdd85a0112ec15400c8cbffea70d0f9c3407491f672a2fad47915e2de"
      url: "https://pub.dev"
    source: hosted
    version: "11.0.2"
  leak_tracker_flutter_testing:
    dependency: transitive
    description:
      name: leak_tracker_flutter_testing
      sha256: "1dbc140bb5a23c75ea9c4811222756104fbcd1a27173f0c34ca01e16bea473c1"
      url: "https://pub.dev"
    source: hosted
    version: "3.0.10"
  leak_tracker_testing:
    dependency: transitive
    description:
      name: leak_tracker_testing
      sha256: "8d5a2d49f4a66b49744b23b018848400d23e54caf9463f4eb20df3eb8acb2eb1"
      url: "https://pub.dev"
    source: hosted
    version: "3.0.2"
  lints:
    dependency: transitive
    description:
      name: lints
      sha256: "12f842a479589fea194fe5c5a3095abc7be0c1f2ddfa9a0e76aed1dbd26a87df"
      url: "https://pub.dev"
    source: hosted
    version: "6.1.0"
  logging:
    dependency: transitive
    description:
      name: logging
      sha256: c8245ada5f1717ed44271ed1c26b8ce85ca3228fd2ffdb75468ab01979309d61
      url: "https://pub.dev"
    source: hosted
    version: "1.3.0"
  matcher:
    dependency: transitive
    description:
      name: matcher
      sha256: "31bd099b47c10cd1aeb55146a2d46ce0277630ecef3f7dae54ad7873f36696cd"
      url: "https://pub.dev"
    source: hosted
    version: "0.12.20"
  material_color_utilities:
    dependency: transitive
    description:
      name: material_color_utilities
      sha256: "9c337007e82b1889149c82ed242ed1cb24a66044e30979c44912381e9be4c48b"
      url: "https://pub.dev"
    source: hosted
    version: "0.13.0"
  meta:
    dependency: transitive
    description:
      name: meta
      sha256: c82594181e3312f3d0695fc95aaaf7758d75b8d4ae2bbecf223b9fd5109a059d
      url: "https://pub.dev"
    source: hosted
    version: "1.18.3"
  mime:
    dependency: transitive
    description:
      name: mime
      sha256: bd47de35f07e27267e69c8c8b22edf9473bfee170a60d60fcc93730c5144b7f6
      url: "https://pub.dev"
    source: hosted
    version: "2.1.0"
  mobile_scanner:
    dependency: "direct main"
    description:
      name: mobile_scanner
      sha256: ce3f059ebd6dbfab7292bba0e893e354b46730636820d3c9ef69005ce2d55bce
      url: "https://pub.dev"
    source: hosted
    version: "7.4.0"
  objective_c:
    dependency: transitive
    description:
      name: objective_c
      sha256: b7fb95a6d9a4f009edd63dc5ac69f07420b23a16161c6dd8660290b59c602e8e
      url: "https://pub.dev"
    source: hosted
    version: "9.5.0"
  package_config:
    dependency: transitive
    description:
      name: package_config
      sha256: ffcf4cf3d6c0b74ac43708d9f56625506e8a68aa935abe9d267a7330f320eb5d
      url: "https://pub.dev"
    source: hosted
    version: "3.0.0"
  path:
    dependency: "direct main"
    description:
      name: path
      sha256: "75cca69d1490965be98c73ceaea117e8a04dd21217b37b292c9ddbec0d955bc5"
      url: "https://pub.dev"
    source: hosted
    version: "1.9.1"
  path_provider:
    dependency: "direct main"
    description:
      name: path_provider
      sha256: a7f4874f987173da295a61c181b8ee71dab59b332a486b391babf26a1b884825
      url: "https://pub.dev"
    source: hosted
    version: "2.1.6"
  path_provider_android:
    dependency: transitive
    description:
      name: path_provider_android
      sha256: "69cbd515a62b94d32a7944f086b2f82b4ac40a1d45bebfc00813a430ab2dabcd"
      url: "https://pub.dev"
    source: hosted
    version: "2.3.1"
  path_provider_foundation:
    dependency: transitive
    description:
      name: path_provider_foundation
      sha256: "2a376b7d6392d80cd3705782d2caa734ca4727776db0b6ec36ef3f1855197699"
      url: "https://pub.dev"
    source: hosted
    version: "2.6.0"
  path_provider_linux:
    dependency: transitive
    description:
      name: path_provider_linux
      sha256: "58c2005f147315b11e9b4a7bc889cd5203e250cba8e3f012dae259b4972b5c16"
      url: "https://pub.dev"
    source: hosted
    version: "2.2.2"
  path_provider_platform_interface:
    dependency: transitive
    description:
      name: path_provider_platform_interface
      sha256: "484838772624c3a4b94f1e44a3e19897fee738f2d5c4ce448443b0417f7c9dda"
      url: "https://pub.dev"
    source: hosted
    version: "2.1.3"
  path_provider_windows:
    dependency: transitive
    description:
      name: path_provider_windows
      sha256: bd6f00dbd873bfb70d0761682da2b3a2c2fccc2b9e84c495821639601d81afe7
      url: "https://pub.dev"
    source: hosted
    version: "2.3.0"
  petitparser:
    dependency: transitive
    description:
      name: petitparser
      sha256: "91bd59303e9f769f108f8df05e371341b15d59e995e6806aefab827b58336675"
      url: "https://pub.dev"
    source: hosted
    version: "7.0.2"
  platform:
    dependency: transitive
    description:
      name: platform
      sha256: "5d6b1b0036a5f331ebc77c850ebc8506cbc1e9416c27e59b439f917a902a4984"
      url: "https://pub.dev"
    source: hosted
    version: "3.1.6"
  plugin_platform_interface:
    dependency: transitive
    description:
      name: plugin_platform_interface
      sha256: "4820fbfdb9478b1ebae27888254d445073732dae3d6ea81f0b7e06d5dedc3f02"
      url: "https://pub.dev"
    source: hosted
    version: "2.1.8"
  pointycastle:
    dependency: transitive
    description:
      name: pointycastle
      sha256: "92aa3841d083cc4b0f4709b5c74fd6409a3e6ba833ffc7dc6a8fee096366acf5"
      url: "https://pub.dev"
    source: hosted
    version: "4.0.0"
  posix:
    dependency: transitive
    description:
      name: posix
      sha256: bc1bad54ad2b735816e31f8d4600cfde6c7839975085ddfbca48b6c9f7c4044e
      url: "https://pub.dev"
    source: hosted
    version: "6.5.2"
  pub_semver:
    dependency: transitive
    description:
      name: pub_semver
      sha256: "261236774e8b1d69cfc6b9eabbc96c40f25e7a2d6b171f3385d4f65d5734fb24"
      url: "https://pub.dev"
    source: hosted
    version: "2.2.1"
  qr:
    dependency: transitive
    description:
      name: qr
      sha256: "5a1d2586170e172b8a8c8470bbbffd5eb0cd38a66c0d77155ea138d3af3a4445"
      url: "https://pub.dev"
    source: hosted
    version: "3.0.2"
  qr_flutter:
    dependency: "direct main"
    description:
      name: qr_flutter
      sha256: "5095f0fc6e3f71d08adef8feccc8cea4f12eec18a2e31c2e8d82cb6019f4b097"
      url: "https://pub.dev"
    source: hosted
    version: "4.1.0"
  record_use:
    dependency: transitive
    description:
      name: record_use
      sha256: "2551bd8eecfe95d14ae75f6021ad0248be5c27f138c2ec12fcb52b500b3ba1ed"
      url: "https://pub.dev"
    source: hosted
    version: "0.6.0"
  share_plus:
    dependency: "direct main"
    description:
      name: share_plus
      sha256: "34f00f9becd2743c1fb05363d624f9f70d37f7ccdcdda47450bc0b8c9d327b8c"
      url: "https://pub.dev"
    source: hosted
    version: "13.3.0"
  share_plus_platform_interface:
    dependency: transitive
    description:
      name: share_plus_platform_interface
      sha256: "365ef7379fc22507256adda3385152942ffce08935452bc972c2e52a0bebae41"
      url: "https://pub.dev"
    source: hosted
    version: "7.2.0"
  sky_engine:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.0"
  source_span:
    dependency: transitive
    description:
      name: source_span
      sha256: "56a02f1f4cd1a2d96303c0144c93bd6d909eea6bee6bf5a0e0b685edbd4c47ab"
      url: "https://pub.dev"
    source: hosted
    version: "1.10.2"
  stack_trace:
    dependency: transitive
    description:
      name: stack_trace
      sha256: "277654b3034d17ac6f9f1cb5595db011b1d5d41e8806866db28e0abaa101c490"
      url: "https://pub.dev"
    source: hosted
    version: "1.12.2"
  stream_channel:
    dependency: transitive
    description:
      name: stream_channel
      sha256: "969e04c80b8bcdf826f8f16579c7b14d780458bd97f56d107d3950fdbeef059d"
      url: "https://pub.dev"
    source: hosted
    version: "2.1.4"
  string_scanner:
    dependency: transitive
    description:
      name: string_scanner
      sha256: "921cd31725b72fe181906c6a94d987c78e3b98c2e205b397ea399d4054872b43"
      url: "https://pub.dev"
    source: hosted
    version: "1.4.1"
  term_glyph:
    dependency: transitive
    description:
      name: term_glyph
      sha256: "7f554798625ea768a7518313e58f83891c7f5024f88e46e7182a4558850a4b8e"
      url: "https://pub.dev"
    source: hosted
    version: "1.2.2"
  test_api:
    dependency: transitive
    description:
      name: test_api
      sha256: "2a122cbe059f8b610d3a5415f42e255b6c17b1f21eee1d960f31080237fb4f11"
      url: "https://pub.dev"
    source: hosted
    version: "0.7.12"
  typed_data:
    dependency: transitive
    description:
      name: typed_data
      sha256: f9049c039ebfeb4cf7a7104a675823cd72dba8297f264b6637062516699fa006
      url: "https://pub.dev"
    source: hosted
    version: "1.4.0"
  url_launcher:
    dependency: "direct main"
    description:
      name: url_launcher
      sha256: f6a7e5c4835bb4e3026a04793a4199ca2d14c739ec378fdfe23fc8075d0439f8
      url: "https://pub.dev"
    source: hosted
    version: "6.3.2"
  url_launcher_android:
    dependency: transitive
    description:
      name: url_launcher_android
      sha256: "611e87fb320b70d1dd721dc46af89c98aceccea9b31fde49e084591414e0c610"
      url: "https://pub.dev"
    source: hosted
    version: "6.3.33"
  url_launcher_ios:
    dependency: transitive
    description:
      name: url_launcher_ios
      sha256: "8faa1aab294f1ab4040b43660c887b0418d5fa4f0cffef76a484e6aa1092eb4a"
      url: "https://pub.dev"
    source: hosted
    version: "6.4.2"
  url_launcher_linux:
    dependency: transitive
    description:
      name: url_launcher_linux
      sha256: "10f86fef4c2c43563fa6c211ff9cf757adf4d3ab762c56bd430664a947d70cd0"
      url: "https://pub.dev"
    source: hosted
    version: "3.2.3"
  url_launcher_macos:
    dependency: transitive
    description:
      name: url_launcher_macos
      sha256: "5e835a3b869c2d70325349c81c5a45c28e20791265b67b2669da6b08c5cd5201"
      url: "https://pub.dev"
    source: hosted
    version: "3.2.6"
  url_launcher_platform_interface:
    dependency: transitive
    description:
      name: url_launcher_platform_interface
      sha256: "552f8a1e663569be95a8190206a38187b531910283c3e982193e4f2733f01029"
      url: "https://pub.dev"
    source: hosted
    version: "2.3.2"
  url_launcher_web:
    dependency: transitive
    description:
      name: url_launcher_web
      sha256: "85c81589622fbc87c1c683aaea164d3604a7777495a79d91e39ffcdec39ddb34"
      url: "https://pub.dev"
    source: hosted
    version: "2.4.3"
  url_launcher_windows:
    dependency: transitive
    description:
      name: url_launcher_windows
      sha256: "6c5ad3f22cd4c38e089b81963b3cd7bb83b111b2df5dce008bb066162f42e429"
      url: "https://pub.dev"
    source: hosted
    version: "3.1.6"
  uuid:
    dependency: transitive
    description:
      name: uuid
      sha256: "9b129329f58692f6e6578329498a8fe9fbe98f090beb764ffbb8ee2eadd01dcd"
      url: "https://pub.dev"
    source: hosted
    version: "4.6.0"
  vector_math:
    dependency: transitive
    description:
      name: vector_math
      sha256: "1d774bbdf6b72a0b12122fc1560c9c2d2a67db5a4a4cc2bd8a5c990ab20e3188"
      url: "https://pub.dev"
    source: hosted
    version: "2.4.0"
  vm_service:
    dependency: transitive
    description:
      name: vm_service
      sha256: "5f37239c4851efcef929cea7824e76df7f2f0970aef85d66bbc430afa40e72f0"
      url: "https://pub.dev"
    source: hosted
    version: "15.3.0"
  web:
    dependency: transitive
    description:
      name: web
      sha256: "868d88a33d8a87b18ffc05f9f030ba328ffefba92d6c127917a2ba740f9cfe4a"
      url: "https://pub.dev"
    source: hosted
    version: "1.1.1"
  win32:
    dependency: transitive
    description:
      name: win32
      sha256: a0b93865d5644f11cf6a8c3f6db909f1ec168958b5805f6cc684adea957cd63d
      url: "https://pub.dev"
    source: hosted
    version: "6.4.0"
  windows_file_picker:
    dependency: transitive
    description:
      name: windows_file_picker
      sha256: d999c1c085374724668af0b674a9758d96255c50933faa2ac1cc51eff8308caf
      url: "https://pub.dev"
    source: hosted
    version: "1.2.0"
  xdg_directories:
    dependency: transitive
    description:
      name: xdg_directories
      sha256: "7a3f37b05d989967cdddcbb571f1ea834867ae2faa29725fd085180e0883aa15"
      url: "https://pub.dev"
    source: hosted
    version: "1.1.0"
  xml:
    dependency: transitive
    description:
      name: xml
      sha256: "67f0aff7be013d107995e9b75bf4e7f2c3ef2dfdb2c8e68024bba0a7fd5756a4"
      url: "https://pub.dev"
    source: hosted
    version: "7.0.1"
  yaml:
    dependency: transitive
    description:
      name: yaml
      sha256: f67cdd8e07d3c6329146aaef1ba043542b3134c12489f553ca9a7435d1068aea
      url: "https://pub.dev"
    source: hosted
    version: "3.1.4"
sdks:
  dart: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"
```

### `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` — REGENERATED

```java
package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;

import io.flutter.embedding.engine.FlutterEngine;

/**
 * Generated file. Do not edit.
 * This file is generated by the Flutter tool based on the
 * plugins that support the Android platform.
 */
@Keep
public final class GeneratedPluginRegistrant {
  private static final String TAG = "GeneratedPluginRegistrant";
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    try {
      flutterEngine.getPlugins().add(new com.mr.flutter.plugin.filepicker.FilePickerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin android_file_picker, com.mr.flutter.plugin.filepicker.FilePickerPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.github.dart_lang.jni.JniPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin jni, com.github.dart_lang.jni.JniPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.github.dart_lang.jni_flutter.JniFlutterPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin jni_flutter, com.github.dart_lang.jni_flutter.JniFlutterPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new dev.steenbakker.mobile_scanner.MobileScannerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin mobile_scanner, dev.steenbakker.mobile_scanner.MobileScannerPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new dev.fluttercommunity.plus.share.SharePlusPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin share_plus, dev.fluttercommunity.plus.share.SharePlusPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.urllauncher.UrlLauncherPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin url_launcher_android, io.flutter.plugins.urllauncher.UrlLauncherPlugin", e);
    }
  }
}
```

### `ios/Runner/GeneratedPluginRegistrant.m` — REGENERATED

```objectivec
//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<file_picker_darwin/FilePickerPlugin.h>)
#import <file_picker_darwin/FilePickerPlugin.h>
#else
@import file_picker_darwin;
#endif

#if __has_include(<mobile_scanner/MobileScannerPlugin.h>)
#import <mobile_scanner/MobileScannerPlugin.h>
#else
@import mobile_scanner;
#endif

#if __has_include(<share_plus/FPPSharePlusPlugin.h>)
#import <share_plus/FPPSharePlusPlugin.h>
#else
@import share_plus;
#endif

#if __has_include(<url_launcher_ios/URLLauncherPlugin.h>)
#import <url_launcher_ios/URLLauncherPlugin.h>
#else
@import url_launcher_ios;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FilePickerPlugin registerWithRegistrar:[registry registrarForPlugin:@"FilePickerPlugin"]];
  [MobileScannerPlugin registerWithRegistrar:[registry registrarForPlugin:@"MobileScannerPlugin"]];
  [FPPSharePlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPSharePlusPlugin"]];
  [URLLauncherPlugin registerWithRegistrar:[registry registrarForPlugin:@"URLLauncherPlugin"]];
}

@end
```

## Changed Files

NEW: Files 26–30 in order. UPDATED: File 1 (version/dependency), File 23 (optional backend capability and additive query/config options), File 25 (new routes, existing views/actions preserved). pubspec.lock and generated Android/iOS plugin registrants changed for the native URL-launch plugin. Their complete current content is included above.

All original test files, transfer/user/wallet/offer domain models, the file-sharing home, TLS/pairing/progress/history services and Android/iOS permission configuration are retained. Old class/enum/function names in updated files remain.

## Dependencies

New exact direct dependency: **url_launcher 6.3.2**, used for explicit user-consented, allowlisted HTTPS provider/store destinations. No existing direct dependency was removed. Resolved new native packages include url_launcher_android 6.3.33, url_launcher_ios 6.4.2 and url_launcher_macos 3.2.6 in the supplied lockfile. This is not an ad SDK or attribution verifier.

## Existing Logic Preserved

The same ShareCoinService/backend identity and existing models are reused; no second wallet. Existing manual/QR sharing, receiver approval, certificate-pinned TLS and v1 endpoints, file picker/selection, streaming/hash/receipt/cancel/retry behavior, saved history, native share and lifecycle protections remain. Rewards never gate local sharing. Limits remain 50 files, 2 GiB/file, 4 GiB/batch, 10-minute invitation and 60-second receiver approval.

Existing referral and guarded withdrawal UI remain available. Original File 25 catalog/config/history views remain reachable through information actions, while new routes provide scalable browsing.

## API Contract

The existing ShareCoinOperation enum and original default operation payloads remain. Optional minimumReward/maximumReward query fields are added only when requested. Fresh-only ad/daily configuration can opt out of cache.

The optional **ShareCoinRewardBackend** capability uses the same authenticated backend instance/scope and response envelope. New capabilities:

- transaction: retrieve a ShareCoinTransaction by ID;
- prepareReward: reserve/check a source/target reward session with a request idempotency key;
- sessionStatus: reconcile by sessionId or original requestKey;
- offerLaunch: return a scoped expiring HTTPS launch grant for an existing startId and platform.

These are contracts, not a deployed server or hard-coded remote host. Full schemas, suggested endpoint mappings, quota semantics and provider requirements are in `docs/PART_06_BACKEND_CONTRACT.md`.

Trusted image/link origins must be configured by the app operator. Defaults deny external resources. The backend must validate redirect/attribution chains; the client can restrict initial launches but cannot independently audit every subsequent external-browser redirect.

## ShareCoin Flow

**User action → tracking/session → provider evidence → existing RewardEvent → backend validation → durable transaction → wallet refresh.**

A start, click, install or provider callback alone is not credit. Completed offer/reward amounts are displayed only after a fresh matching completed credit transaction. The amount comes from that transaction, not the catalog promise. Rejected/reversed/pending outcomes remain visible. There is no client balance increment.

A daily reward uses backend policy/time and a server-issued reference. A promotion click creates tracking only, not a claim that coins were earned. RewardedAdAdapter must wrap a real compliant SDK; the supplied production default is explicitly unavailable.

## Withdrawal Flow

**Backend wallet → idempotent request → server validation/reservation → payout provider/admin → backend status update → wallet refresh.**

Part 5 minimum/balance/fee/policy/destination/conflict validation and status-by-key reconciliation remain. No local subtraction, refund or paid flag is treated as real payment. bKash/Nagad/Rocket/PayPal/Bank remain configuration choices, not connected providers.

## Anti-Fraud Requirements

The backend must authenticate/authorize users, verify provider signatures/SSV/attribution, bind sessions and actions, compute amounts, enforce event uniqueness and payload-bound idempotency, reserve quotas atomically, apply server-time/country/referral/risk/rate policies and maintain financially consistent ledger/payout/audit/reversal flows.

Client guards are bounded and memory-only. They cannot secure real money against modified clients, account farms or multiple devices. A client timer never grants credit or resets a backend daily limit. Interrupted activity must be reconciled by server IDs/history, not blindly resubmitted.

## Test Coverage

Actually executed with Flutter 3.47.2 / Dart 3.13.2 on Linux:

- Previous tests retained: **204**, byte-identical files.
- New File 30 tests: **54**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter expanded`: **258 tests passed**.

Coverage includes 300-offer pagination/scrolling/filter/search/sort, 1,020-offer bounded windows, duplicate IDs and starts, expiry and delayed consent, state/ledger consistency, duplicate/premature/stale ad callbacks, backend signature rejection mapping, cooldown/daily limits, daily/promotion flow, withdrawal/referral/transaction regression, account/disposal/background behavior, offline/cache handling, bounded images, lazy rendering and original sharing navigation.

The catalog/provider/credit fixtures are test-only. These results do not prove real advertiser inventory, native ad playback, actual provider signatures/attribution, payouts, real phones/camera/two-phone Wi-Fi, native/production builds or stores.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

**Full stop/rebuild is required** for the added url_launcher native plugin; hot reload alone is insufficient. Android needs a compatible JDK/Android SDK; iPhone building requires Mac/Xcode/signing. Existing permissions/runner settings were not weakened. No APK/IPA is delivered or claimed verified.

## Manual Testing

**Manual/device/staging verification required — not performed here.**

1. Android: confirm the original sharing home, Send/Receive, QR/manual pairing, Saved Files/history and theme remain accessible. Open ShareCoin → Offers and return without losing selection.
2. Default build: verify setup/unavailable states and no seeded production catalog, fake balance or simulated paid ad.
3. With an authenticated staging backend, provide at least 300 lightweight offers. Scroll to the end, search/filter/sort/refresh, test cached/offline data, broken images and windows beyond 500 records. Configure reviewed image/provider origins explicitly.
4. Read an offer's terms, accept tracking consent, confirm its allowed domain and launch a development provider/store URL. Decline once; let a grant expire while reviewing once. Start/open/install must not produce credit. Return and check backend status/transaction.
5. With a compliant real native ad adapter and development units, test load/ready/show/complete/skip/failure, duplicate and stale callbacks, interruptions, cooldown and daily limits. Validate provider evidence on the server and verify pending/approved/rejected/reversed ledger outcomes without local coin arithmetic.
6. Test promotion tracking without click credit, backend daily eligibility without device-date trust, qualified referral summaries and ledger reversal visibility.
7. With staging payout configuration only, test minimum/balance/conflicting requests, duplicate keys, changed quotes, lost responses and original-key status reconciliation. Do not treat staging records as real payments.
8. Test private Wi-Fi with reward internet unavailable. On two real phones, exercise the original TLS transfer, approval, progress/cancel/retry, receipt, saved history and SHA-256.
9. iPhone: repeat applicable HTTPS store launch, app-background transitions, local-network/camera permissions, TLS sharing and native export. Widget/emulator results are not a substitute.

## Known Limitations

Live authentication/backend transport, advertiser catalog/attribution, a real rewarded-ad SDK/provider and payout services are not connected by default. Optional extension methods and the adapter are client contracts, not a deployed earning system. Production data requires those integrations.

The UI uses bounded windows/caches and recent-ID/cursor tracking; it is not an unlimited offline archive. Server pagination must be stable/unique. Image/link trust and external redirect chains require operator/provider review. Client clocks/duplicate guards are not financial authority. Provider/backend work may finish while the app is away and need status/history reconciliation. Native/device/build/store verification and existing foreground/private-IPv4/no-resume file-sharing limitations remain.

# ▶ Next — Part 7 (File 31–35)
