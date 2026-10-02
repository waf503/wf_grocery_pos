// Manejo de dinero en CENTAVOS enteros.
//
// Los `double` no representan bien los decimales (0.1 + 0.2 != 0.3), y
// sumar totales de venta o cuadrar una caja con ellos acumula errores de
// centavos. Todo monto que se guarda en la base de datos (ventas, caja)
// va como `int` de centavos; la UI sigue mostrando `double` convertido en
// el borde con estas dos funciones.

/// 12.34 → 1234. Redondea al centavo más cercano (mitades hacia arriba).
int toCents(double amount) => (amount * 100).round();

/// 1234 → 12.34.
double fromCents(int cents) => cents / 100;
