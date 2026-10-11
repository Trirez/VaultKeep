import 'package:flutter/material.dart';

import '../theme.dart';
import '../vault_controller.dart';

/// Enpass 1:1 Home Security Score & Password Audit Dashboard (`Enpass_UNGNDpANfa.png`, `Enpass_4B5a9NsMjk.png`).
class HomeDashboardPane extends StatelessWidget {
  const HomeDashboardPane({
    super.key,
    required this.controller,
  });

  final VaultController controller;

  Color _scoreColor(int score) {
    if (score >= 85) return TacticalTheme.emeraldReady;
    if (score >= 70) return TacticalTheme.cyanTactical;
    if (score >= 50) return TacticalTheme.amberPrimary;
    return TacticalTheme.crimsonDanger;
  }

  void _showScoreMeaningDialog(BuildContext context, int score, String label) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TacticalTheme.bgSurface,
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: TacticalTheme.amberPrimary),
            const SizedBox(width: 8),
            const Expanded(child: Text('What does this score mean?')),
          ],
        ),
        content: Text(
          'Your Security Score ($score% â€” $label) is calculated 100% offline inside the Rust KDBX4 core based on password entropy, uniqueness across items, compromised/breached advisories, Passkey/2FA readiness, and expiration timestamps.',
          style: TextStyle(
            fontSize: 13,
            color: TacticalTheme.textSecondary,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = controller.overallSecurityScore;
    final label = controller.overallSecurityLabel;
    final totalItems = controller.activeItems.length;
    final scoreColor = _scoreColor(score);

    final cards = <_AuditCardSpec>[
      _AuditCardSpec(
        key: const ValueKey('audit_card_excellent'),
        title: 'Excellent',
        subtitle: 'High-entropy unique credentials',
        count: controller.excellentCount,
        icon: Icons.verified_outlined,
        accent: TacticalTheme.emeraldReady,
        filter: VaultCategoryFilter.auditExcellent,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_compromised'),
        title: 'Compromised',
        subtitle: 'Flagged in compromised advisories',
        count: controller.compromisedCount,
        icon: Icons.gpp_bad_outlined,
        accent: TacticalTheme.crimsonDanger,
        filter: VaultCategoryFilter.auditCompromised,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_weak'),
        title: 'Weak',
        subtitle: 'Low entropy or dictionary patterns',
        count: controller.weakCount,
        icon: Icons.warning_amber_rounded,
        accent: TacticalTheme.amberPrimary,
        filter: VaultCategoryFilter.auditWeak,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_passkey_supported'),
        title: 'Passkey Supported',
        subtitle: 'Upgradeable to FIDO2 / WebAuthn',
        count: controller.passkeySupportedCount,
        icon: Icons.fingerprint,
        accent: TacticalTheme.cyanTactical,
        filter: VaultCategoryFilter.passkeySupported,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_breached'),
        title: 'Breached',
        subtitle: 'Known breached corpus match',
        count: controller.breachedCount,
        icon: Icons.report_problem_outlined,
        accent: TacticalTheme.crimsonDanger,
        filter: VaultCategoryFilter.auditBreached,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_identical'),
        title: 'Identical',
        subtitle: 'Reused across multiple items',
        count: controller.identicalCount,
        icon: Icons.copy_all_outlined,
        accent: TacticalTheme.amberBright,
        filter: VaultCategoryFilter.auditIdentical,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_2fa_supported'),
        title: '2FA-supported',
        subtitle: 'Supports TOTP two-factor auth',
        count: controller.twoFaSupportedCount,
        icon: Icons.phonelink_lock_outlined,
        accent: TacticalTheme.cyanTactical,
        filter: VaultCategoryFilter.auditTwoFaSupported,
      ),
      _AuditCardSpec(
        key: const ValueKey('audit_card_expired'),
        title: 'Expired',
        subtitle: 'Past KDBX4 expiry timestamp',
        count: controller.expiredCount,
        icon: Icons.schedule_outlined,
        accent: TacticalTheme.crimsonLight,
        filter: VaultCategoryFilter.auditExpired,
      ),
    ];

    return Container(
      key: const ValueKey('enpass_home_dashboard'),
      color: TacticalTheme.bgDeepCarbon,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Top Enpass `Home` Header + Pro Crown Badge (`Enpass_UNGNDpANfa.png`)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Home',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: TacticalTheme.textPrimary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: TacticalTheme.amberDim,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: TacticalTheme.amberPrimary,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspace_premium,
                          size: 15,
                          color: TacticalTheme.amberBright,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'VaultKeep Pro',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.amberBright,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('home_button_view_all_items'),
                    icon: Icon(
                      Icons.list_alt,
                      size: 16,
                      color: TacticalTheme.amberPrimary,
                    ),
                    label: Text(
                      'View All Items ($totalItems)',
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TacticalTheme.amberPrimary,
                      ),
                    ),
                    onPressed: () => controller.selectGroup(null),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Enpass `Security Score` Card (`Enpass_UNGNDpANfa.png`)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: TacticalTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: TacticalTheme.borderTech, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Security Score',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: TacticalTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            key: const ValueKey('home_button_score_meaning'),
                            onTap: () => _showScoreMeaningDialog(
                              context,
                              score,
                              label,
                            ),
                            child: Text(
                              'What does this score mean?',
                              style: TextStyle(
                                fontSize: 12,
                                color: TacticalTheme.cyanTactical,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (score / 100.0).clamp(0.0, 1.0),
                              minHeight: 7,
                              backgroundColor: TacticalTheme.bgDeepCarbon,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scoreColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SegmentedAmberBar(
                            fraction: score / 100.0,
                            segments: 20,
                            height: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$score',
                          key: const ValueKey('home_security_score_value'),
                          style: TacticalTheme.monoStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          key: const ValueKey('home_security_score_label'),
                          style: TacticalTheme.monoStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: TacticalTheme.borderSubtle, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '$totalItems',
                      style: TacticalTheme.monoStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: TacticalTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Total Items',
                      style: TacticalTheme.monoStyle(
                        fontSize: 13,
                        color: TacticalTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 8 Audit Summary Cards (3-column responsive grid on desktop matching Enpass_UNGNDpANfa.png)
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 760
                  ? 3
                  : (constraints.maxWidth >= 480 ? 2 : 1);
              if (cols == 1) {
                return Column(
                  children: [
                    for (final c in cards) ...[
                      _AuditSummaryCard(
                        spec: c,
                        onTap: () => controller.selectCategory(c.filter),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              final rows = <Widget>[];
              for (var i = 0; i < cards.length; i += cols) {
                final rowChildren = <Widget>[];
                for (var cIdx = 0; cIdx < cols; cIdx++) {
                  if (cIdx > 0) {
                    rowChildren.add(const SizedBox(width: 12));
                  }
                  final itemIdx = i + cIdx;
                  rowChildren.add(
                    Expanded(
                      child: itemIdx < cards.length
                          ? _AuditSummaryCard(
                              spec: cards[itemIdx],
                              onTap: () => controller.selectCategory(
                                cards[itemIdx].filter,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  );
                }
                rows.add(Row(children: rowChildren));
                if (i + cols < cards.length) {
                  rows.add(const SizedBox(height: 12));
                }
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }
}

class _AuditCardSpec {
  const _AuditCardSpec({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.accent,
    required this.filter,
  });

  final Key key;
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color accent;
  final VaultCategoryFilter filter;
}

class _AuditSummaryCard extends StatelessWidget {
  const _AuditSummaryCard({
    required this.spec,
    required this.onTap,
  });

  final _AuditCardSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: spec.key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TacticalTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TacticalTheme.borderTech, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                shape: BoxShape.circle,
                border: Border.all(
                  color: spec.accent.withValues(alpha: 0.65),
                  width: 1.5,
                ),
              ),
              child: Icon(spec.icon, color: spec.accent, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${spec.count} ${spec.count == 1 ? "Item" : "Items"}',
                    style: TacticalTheme.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: TacticalTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spec.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: TacticalTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Tooltip(
              message: spec.subtitle,
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
