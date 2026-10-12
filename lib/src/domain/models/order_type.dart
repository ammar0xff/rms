enum OrderType {
  dineIn('داخل الصالة'),
  takeaway('الاستلام'),
  delivery('توصيل');

  const OrderType(this.label);

  final String label;
}
