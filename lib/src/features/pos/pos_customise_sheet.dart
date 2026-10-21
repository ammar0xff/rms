import 'package:flutter/material.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_grab_handle.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/order.dart';

/// Item Customization Sheet (تخصيص الصنف وملاحظات المطبخ)
///
/// Functional contract:
/// - Required single-choice modifier groups
/// - Optional multi-choice priced options
/// - Kitchen note free text
/// - Calculates unit price with selected modifier deltas
class PosCustomiseSheet extends StatefulWidget {
  const PosCustomiseSheet({
    super.key,
    required this.item,
    required this.onAdd,
  });

  final MenuItemModel item;
  final ValueChanged<OrderItem> onAdd;

  static Future<void> show(
    BuildContext context, {
    required MenuItemModel item,
    required ValueChanged<OrderItem> onAdd,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: PieRadius.topLg),
      builder: (context) => PosCustomiseSheet(item: item, onAdd: onAdd),
    );
  }

  @override
  State<PosCustomiseSheet> createState() => _PosCustomiseSheetState();
}

class _PosCustomiseSheetState extends State<PosCustomiseSheet> {
  final Map<String, String> _singleSelections = {};
  final Set<String> _multiSelections = {};
  final TextEditingController _noteController = TextEditingController();
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    // Default select first option in required single-choice groups
    for (final group in widget.item.modifierGroups) {
      if (group.required && !group.multi && group.options.isNotEmpty) {
        _singleSelections[group.id] = group.options.first.id;
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  double get _currentUnitPrice {
    var price = widget.item.price;
    for (final group in widget.item.modifierGroups) {
      for (final option in group.options) {
        if (_singleSelections[group.id] == option.id || _multiSelections.contains(option.id)) {
          price += option.deltaPrice;
        }
      }
    }
    return price;
  }

  List<String> get _selectedModifierNames {
    final names = <String>[];
    for (final group in widget.item.modifierGroups) {
      for (final option in group.options) {
        if (_singleSelections[group.id] == option.id || _multiSelections.contains(option.id)) {
          names.add(option.name);
        }
      }
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final unitPrice = _currentUnitPrice;
    final totalPrice = unitPrice * _quantity;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: PieColors.surfaceOverlay,
            borderRadius: PieRadius.topLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PieGrabHandle(),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.name,
                            style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          PieNumeral.money(
                            widget.item.price,
                            style: PieTypography.monoBody.copyWith(
                              color: PieColors.cashierAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: PieColors.border, height: 1),

              // Customizations scroll body
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Modifier groups
                    for (final group in widget.item.modifierGroups) ...[
                      Row(
                        children: [
                          Text(
                            group.name,
                            style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          if (group.required)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: PieColors.cashierSurface,
                                borderRadius: PieRadius.borderSm,
                              ),
                              child: Text(
                                'مطلوب',
                                style: PieTypography.caption.copyWith(
                                  color: PieColors.cashierAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (group.multi)
                        _buildMultiOptions(group)
                      else
                        _buildSingleOptions(group),
                      const SizedBox(height: 20),
                    ],

                    // Kitchen Note
                    Text(
                      'ملاحظات المطبخ',
                      style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      style: PieTypography.body.copyWith(color: PieColors.ink),
                      decoration: const InputDecoration(
                        hintText: 'مثلاً: بدون بصل، صوص خارجي، تحمير زيادة...',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // Bottom Sticky Action Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: PieColors.surface1,
                  border: Border(top: BorderSide(color: PieColors.border, width: 1)),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      // Quantity Stepper
                      Container(
                        decoration: BoxDecoration(
                          color: PieColors.surface2,
                          borderRadius: PieRadius.borderMd,
                          border: Border.all(color: PieColors.border),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18, color: PieColors.ink),
                              onPressed: _quantity > 1
                                  ? () => setState(() => _quantity--)
                                  : null,
                            ),
                            PieNumeral.count(
                              _quantity,
                              style: PieTypography.monoHeading,
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18, color: PieColors.ink),
                              onPressed: () => setState(() => _quantity++),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Add to Cart Button
                      Expanded(
                        child: PieButton.primary(
                          onPressed: () {
                            final orderItem = OrderItem(
                              productId: widget.item.id,
                              name: widget.item.name,
                              unitPrice: unitPrice,
                              quantity: _quantity,
                              station: widget.item.station,
                              note: _noteController.text.trim().isEmpty
                                  ? null
                                  : _noteController.text.trim(),
                              modifiers: _selectedModifierNames,
                            );
                            widget.onAdd(orderItem);
                            Navigator.of(context).pop();
                          },
                          label: 'إضافة للأوردر • ${PieTypography.formatEgp(totalPrice)}',
                          accentColor: PieColors.cashierAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleOptions(ModifierGroup group) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: group.options.map((option) {
        final isSelected = _singleSelections[group.id] == option.id;

        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.name,
                style: PieTypography.body.copyWith(
                  color: isSelected ? const Color(0xFF0F1117) : PieColors.inkSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (option.deltaPrice > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+${option.deltaPrice.toStringAsFixed(0)} ج.م',
                  style: PieTypography.caption.copyWith(
                    color: isSelected ? const Color(0xFF0F1117) : PieColors.cashierAccent,
                  ),
                ),
              ],
            ],
          ),
          selected: isSelected,
          selectedColor: PieColors.cashierAccent,
          backgroundColor: PieColors.surface2,
          side: BorderSide(
            color: isSelected ? PieColors.cashierAccent : PieColors.border,
          ),
          onSelected: (selected) {
            if (selected) {
              setState(() => _singleSelections[group.id] = option.id);
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildMultiOptions(ModifierGroup group) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: group.options.map((option) {
        final isSelected = _multiSelections.contains(option.id);

        return FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.name,
                style: PieTypography.body.copyWith(
                  color: isSelected ? const Color(0xFF0F1117) : PieColors.inkSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (option.deltaPrice > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+${option.deltaPrice.toStringAsFixed(0)} ج.م',
                  style: PieTypography.caption.copyWith(
                    color: isSelected ? const Color(0xFF0F1117) : PieColors.cashierAccent,
                  ),
                ),
              ],
            ],
          ),
          selected: isSelected,
          selectedColor: PieColors.cashierAccent,
          backgroundColor: PieColors.surface2,
          side: BorderSide(
            color: isSelected ? PieColors.cashierAccent : PieColors.border,
          ),
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _multiSelections.add(option.id);
              } else {
                _multiSelections.remove(option.id);
              }
            });
          },
        );
      }).toList(),
    );
  }
}
