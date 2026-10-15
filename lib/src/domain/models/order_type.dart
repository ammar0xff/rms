enum OrderType {
  dineIn('صالة'),
  takeaway('تيك أواي'),
  delivery('توصيل');

  const OrderType(this.label);

  final String label;
}
