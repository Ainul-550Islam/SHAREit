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
