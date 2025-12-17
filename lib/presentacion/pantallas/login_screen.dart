import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../negocio/providers/auth_provider.dart';
import '../../datos/api_services/storage_service.dart';
import '../../datos/api_services/biometric_auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailOrPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _savedIdentifier;
  String? _lastShownError;

  // Biometric
  final _biometricService = BiometricAuthService();
  final _storage = StorageService();
  bool _isBiometricAvailable = false;
  bool _hasBiometricData = false;
  String _biometricMessage = '';

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Inicializar animaciones
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    // Iniciar animaciones
    _fadeController.forward();
    _slideController.forward();

    // Cargar identificador guardado y verificar biometría
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeBiometric();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final emailOrPhone = _emailOrPhoneController.text.trim();
    final password = _passwordController.text.trim();

    try {
      await ref
          .read(authProvider.notifier)
          .login(emailOrPhone, password, rememberMe: true);
      // La navegación se maneja automáticamente por el cambio de estado en main.dart
    } catch (e) {
      // El error se maneja en el listener
    }
  }

  Future<void> _handleChangeAccount() async {
    final storage = StorageService();
    await storage.clearSavedIdentifier();
    await storage.clearBiometricData();
    setState(() {
      _savedIdentifier = null;
      _emailOrPhoneController.clear();
      _passwordController.clear();
      _hasBiometricData = false;
    });
  }

  Future<void> _initializeBiometric() async {
    // Cargar identificador guardado
    final saved = await _storage.getSavedIdentifier();

    // Verificar si hay biometría disponible
    final isAvailable = await _biometricService.isBiometricAvailable();
    final hasBiometricData = await _storage.hasBiometricData();
    final biometricMessage = await _biometricService.getAvailableBiometricsMessage();

    if (mounted) {
      setState(() {
        _savedIdentifier = saved;
        if (saved != null) {
          _emailOrPhoneController.text = saved;
        }
        _isBiometricAvailable = isAvailable;
        _hasBiometricData = hasBiometricData;
        _biometricMessage = biometricMessage;
      });

      // Si hay datos biométricos y está habilitado, intentar autenticar automáticamente
      if (_hasBiometricData) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _handleBiometricLogin();
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    try {
      // Autenticar con biometría
      final authenticated = await _biometricService.authenticateForLogin();

      if (!authenticated) {
        return; // Usuario canceló o falló la autenticación
      }

      // Obtener credenciales guardadas
      final identifier = await _storage.getSavedIdentifier();
      final password = await _storage.getBiometricPassword();

      if (identifier == null || password == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay credenciales guardadas'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Realizar login
      await ref
          .read(authProvider.notifier)
          .login(identifier, password, rememberMe: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en autenticación biométrica: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEnableBiometricDialog() async {
    if (!_isBiometricAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La autenticación biométrica no está disponible en este dispositivo'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activar autenticación biométrica'),
        content: Text(
          '¿Deseas activar el inicio de sesión con $_biometricMessage?\n\n'
          'Tus credenciales se guardarán de forma segura en el dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _enableBiometric();
    }
  }

  Future<void> _enableBiometric() async {
    try {
      // Verificar autenticación biométrica
      final authenticated = await _biometricService.authenticate(
        localizedReason: 'Autentícate para activar el inicio de sesión biométrico',
      );

      if (!authenticated) {
        return;
      }

      // Guardar preferencias y credenciales
      await _storage.setBiometricEnabled(true);
      await _storage.saveBiometricPassword(_passwordController.text);
      await _storage.setSavedIdentifier(_emailOrPhoneController.text);

      if (mounted) {
        setState(() {
          _hasBiometricData = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Autenticación biométrica activada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al activar biometría: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Listener para errores y login exitoso
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.error != null && next.error != _lastShownError) {
        _lastShownError = next.error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }

      // Mostrar diálogo para activar biometría después de login exitoso
      if (previous?.usuario == null &&
          next.usuario != null &&
          _isBiometricAvailable &&
          !_hasBiometricData) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _showEnableBiometricDialog();
          }
        });
      }
    });

    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    colorScheme.surface,
                    colorScheme.surface.withOpacity(0.8),
                    colorScheme.primaryContainer.withOpacity(0.3),
                  ]
                : [
                    colorScheme.primary.withOpacity(0.1),
                    colorScheme.secondary.withOpacity(0.1),
                    colorScheme.tertiary.withOpacity(0.05),
                  ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo con animación
                        /*Hero(
                          tag: 'app_logo',
                          child: Container(
                            width: 120,
                            height: 120,
                            margin: const EdgeInsets.only(bottom: 32),
                            decoration: BoxDecoration(
                              shape: BoxShape.rectangle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.secondary,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            //colocar imagen assets
                            child: const Center(
                              child: Image(
                                image: AssetImage('assets/icons/icon.png'),
                                fit: BoxFit.contain,
                              )),
                          ),
                        ),*/
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: const Image(
                                image: AssetImage('assets/icons/icon.png'),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Título
                        Text(
                          'Bienvenido',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Inicia sesión para continuar',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Card de login con glassmorphism
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? colorScheme.surface.withOpacity(0.6)
                                : Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Usuario guardado
                                  if (_savedIdentifier != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer
                                            .withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                colorScheme.primary,
                                            child: Icon(
                                              Icons.person,
                                              color: colorScheme.onPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _savedIdentifier!,
                                                  style: theme
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: colorScheme
                                                            .onSurface,
                                                      ),
                                                ),
                                                Text(
                                                  'Usuario guardado',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.change_circle_outlined,
                                            ),
                                            onPressed: _handleChangeAccount,
                                            tooltip: 'Cambiar cuenta',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],

                                  // Campo de Email/Teléfono (solo si no hay usuario guardado)
                                  if (_savedIdentifier == null) ...[
                                    TextFormField(
                                      controller: _emailOrPhoneController,
                                      decoration: InputDecoration(
                                        labelText: 'Email, teléfono o usuario',
                                        hintText:
                                            'ejemplo@correo.com o 70123456',
                                        prefixIcon: Icon(
                                          Icons.person_outline_rounded,
                                          color: colorScheme.primary,
                                        ),
                                        filled: true,
                                        fillColor: colorScheme.surfaceContainer
                                            .withOpacity(0.5),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: colorScheme.outline
                                                .withOpacity(0.2),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: colorScheme.primary,
                                            width: 2,
                                          ),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: colorScheme.error,
                                          ),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: colorScheme.error,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Por favor ingresa tu usuario';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                  ],

                                  // Campo de Contraseña
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      hintText: 'Ingresa tu contraseña',
                                      prefixIcon: Icon(
                                        Icons.lock_outline_rounded,
                                        color: colorScheme.primary,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainer
                                          .withOpacity(0.5),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: colorScheme.outline
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: colorScheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: colorScheme.error,
                                        ),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: colorScheme.error,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _handleLogin(),
                                    autofocus: _savedIdentifier != null,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Por favor ingresa tu contraseña';
                                      }
                                      if (value.length < 6) {
                                        return 'La contraseña debe tener al menos 6 caracteres';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 32),

                                  // Botón de login
                                  FilledButton(
                                    onPressed: isLoading ? null : _handleLogin,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: colorScheme.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: isLoading
                                        ? SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    colorScheme.onPrimary,
                                                  ),
                                            ),
                                          )
                                        : Text(
                                            'Iniciar Sesión',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.onPrimary,
                                                ),
                                          ),
                                  ),

                                  // Botón de autenticación biométrica
                                  if (_hasBiometricData) ...[
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: isLoading ? null : _handleBiometricLogin,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: colorScheme.primary,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 18,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        side: BorderSide(
                                          color: colorScheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                      icon: Icon(
                                        Icons.fingerprint,
                                        size: 28,
                                        color: colorScheme.primary,
                                      ),
                                      label: Text(
                                        'Usar $_biometricMessage',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Footer
                        const SizedBox(height: 32),
                        Text(
                          'Cobrador LP',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
