/// Rounds to currency cents.
///
/// Money is stored as double, so every write boundary (payables, variances,
/// taxes) rounds here instead of accumulating binary error that later fails
/// exact comparisons — a visually-exact payoff rejected, or a clean drawer
/// showing فرق 0.01. Display formatting rounds independently; this is about
/// what gets stored and compared.
double roundMoney(double value) => (value * 100).round() / 100;
