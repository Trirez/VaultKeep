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
        padding: const EdgeInsets.all(20),
        children: [
          // Top Security Score Banner (Enpass Home Header)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: TacticalTheme.bgSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TacticalTheme.borderTech, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: TacticalTheme.amberDim,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: TacticalTheme.amberPrimary,
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: TacticalTheme.amberBright,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Primary Vault Security Audit',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TacticalTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Offline Zero-Knowledge Password Health & Breach Telemetry',
                              style: TacticalTheme.monoStyle(
                                fontSize: 11,
                                color: TacticalTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('home_button_view_all_items'),
                      icon: const Icon(
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
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 20,
                  runSpacing: 14,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$score',
                          key: const ValueKey('home_security_score_value'),
                          style: TacticalTheme.monoStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Overall Security Score',
                              style: TacticalTheme.monoStyle(
                                fontSize: 12,
                                color: TacticalTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: TacticalTheme.bgDeepCarbon,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: scoreColor, width: 1),
                              ),
                              child: Text(
                                label,
                                key: const ValueKey(
                                  'home_security_score_label',
                                ),
                                style: TacticalTheme.monoStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: scoreColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: TacticalTheme.bgDeepCarbon,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: TacticalTheme.borderTech,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$totalItems',
                            style: TacticalTheme.monoStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: TacticalTheme.amberBright,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Total Items',
                            style: TacticalTheme.monoStyle(
                              fontSize: 12,
                              color: TacticalTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedAmberBar(
                  fraction: score / 100.0,
                  segments: 20,
                  height: 10,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 8 Audit Summary Cards (2-column responsive grid)
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 520;
              if (!twoCols) {
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
              for (var i = 0; i < cards.length; i += 2) {
                rows.add(
                  Row(
                    children: [
                      Expanded(
                        child: _AuditSummaryCard(
                          spec: cards[i],
                          onTap: () =>
                              controller.selectCategory(cards[i].filter),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: i + 1 < cards.length
                            ? _AuditSummaryCard(
                                spec: cards[i + 1],
                                onTap: () => controller.selectCategory(
                                  cards[i + 1].filter,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
                if (i + 2 < cards.length) {
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
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TacticalTheme.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TacticalTheme.borderTech, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: spec.accent.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
              child: Icon(spec.icon, color: spec.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TacticalTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${spec.count} ${spec.count == 1 ? "Item" : "Items"}',
                    style: TacticalTheme.monoStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: spec.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spec.subtitle,
                    style: TacticalTheme.monoStyle(
                      fontSize: 10,
                      color: TacticalTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: TacticalTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
