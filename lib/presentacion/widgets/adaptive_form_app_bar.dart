import 'package:flutter/material.dart';

/// AppBar adaptativo que responde automáticamente al modo oscuro/claro
/// y sigue las guías de Material Design 3
class AdaptiveFormAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Título que se muestra en el AppBar
  final String title;

  /// Si es true, muestra el botón de eliminar
  final bool showDelete;

  /// Callback cuando se presiona el botón de eliminar
  final VoidCallback? onDelete;

  /// Acciones adicionales a mostrar en el AppBar
  final List<Widget>? additionalActions;

  /// Color personalizado para el gradiente (opcional)
  /// Si no se provee, usa el color primario del tema
  final Color? customColor;

  const AdaptiveFormAppBar({
    super.key,
    required this.title,
    this.showDelete = false,
    this.onDelete,
    this.additionalActions,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = customColor ?? Theme.of(context).primaryColor;

    return AppBar(
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isDark ? colorScheme.onSurface : Colors.white,
        ),
      ),
      // iOS centra el título, Android lo alinea a la izquierda
      centerTitle: Theme.of(context).platform == TargetPlatform.iOS,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
              ? [
                  colorScheme.surface,
                  colorScheme.surfaceVariant,
                ]
              : [
                  primaryColor,
                  primaryColor.withOpacity(0.8),
                ],
          ),
        ),
      ),
      foregroundColor: isDark ? colorScheme.onSurface : Colors.white,
      // Material Design 3: elevación 0 en modo oscuro
      elevation: isDark ? 0 : 8,
      // Elevación cuando hay scroll
      scrolledUnderElevation: 3,
      // Surface tint para modo oscuro (MD3)
      surfaceTintColor: isDark ? null : colorScheme.primary,
      shadowColor: isDark
        ? Colors.transparent
        : primaryColor.withOpacity(0.5),
      actions: [
        // Botón de eliminar si está habilitado
        if (showDelete && onDelete != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 26),
              onPressed: onDelete,
              tooltip: 'Eliminar',
              // En modo oscuro usa el color de error del tema
              color: isDark ? colorScheme.error : null,
            ),
          ),
        // Acciones adicionales
        if (additionalActions != null) ...additionalActions!,
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
