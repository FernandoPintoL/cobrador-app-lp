import 'package:local_auth/local_auth.dart';

/// Servicio para manejar la autenticación biométrica
/// Soporta huella dactilar y reconocimiento facial
class BiometricAuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Verifica si el dispositivo soporta autenticación biométrica
  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Verifica si hay biometría disponible en el dispositivo
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Obtiene la lista de tipos de biometría disponibles
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Verifica si hay biometría configurada y disponible
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await canCheckBiometrics();
      if (!canCheck) return false;

      final availableBiometrics = await getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Obtiene un mensaje descriptivo de las biometrías disponibles
  Future<String> getAvailableBiometricsMessage() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.isEmpty) {
      return 'No hay biometría configurada';
    }

    final types = <String>[];
    if (biometrics.contains(BiometricType.face)) {
      types.add('Reconocimiento facial');
    }
    if (biometrics.contains(BiometricType.fingerprint)) {
      types.add('Huella dactilar');
    }
    if (biometrics.contains(BiometricType.iris)) {
      types.add('Iris');
    }
    if (biometrics.contains(BiometricType.strong)) {
      types.add('Biometría fuerte');
    }
    if (biometrics.contains(BiometricType.weak)) {
      types.add('Biometría débil');
    }

    return types.join(' o ');
  }

  /// Autentica al usuario usando biometría
  ///
  /// [localizedReason]: Mensaje que se muestra al usuario explicando por qué se solicita la autenticación
  /// [useErrorDialogs]: Si debe mostrar diálogos de error automáticamente
  /// [stickyAuth]: Si la autenticación debe permanecer activa hasta que sea exitosa o cancelada
  /// [sensitiveTransaction]: Si es una transacción sensible (desactiva algunos atajos)
  ///
  /// Retorna true si la autenticación fue exitosa, false en caso contrario
  Future<bool> authenticate({
    required String localizedReason,
    bool useErrorDialogs = true,
    bool stickyAuth = true,
    bool sensitiveTransaction = true,
  }) async {
    try {
      // Verificar si hay biometría disponible
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      // Intentar autenticar
      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          sensitiveTransaction: sensitiveTransaction,
          biometricOnly: true,
        ),
      );

      return authenticated;
    } catch (e) {
      // Los errores comunes incluyen:
      // - PlatformException: Usuario canceló
      // - PlatformException: Demasiados intentos fallidos
      // - PlatformException: No hay biometría configurada
      return false;
    }
  }

  /// Autentica para el login
  Future<bool> authenticateForLogin() async {
    return authenticate(
      localizedReason: 'Autentícate para iniciar sesión',
      useErrorDialogs: true,
      stickyAuth: true,
    );
  }

  /// Autentica para una transacción sensible
  Future<bool> authenticateForTransaction() async {
    return authenticate(
      localizedReason: 'Confirma tu identidad para continuar',
      useErrorDialogs: true,
      stickyAuth: true,
      sensitiveTransaction: true,
    );
  }

  /// Detiene la autenticación en curso
  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (e) {
      // Ignorar errores al detener
    }
  }
}
