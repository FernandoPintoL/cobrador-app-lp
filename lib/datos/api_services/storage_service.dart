import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../modelos/usuario.dart';
import '../modelos/dashboard_statistics.dart';

class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';
  static const String _lastLoginKey = 'last_login';
  static const String _savedIdentifierKey = 'saved_identifier';
  static const String _requiresReauthKey = 'requires_reauth'; // Nuevo flag para re-autenticación
  static const String _dashboardStatsKey = 'dashboard_statistics'; // Estadísticas del dashboard
  static const String _biometricEnabledKey = 'biometric_enabled'; // Preferencia de autenticación biométrica
  static const String _savedPasswordKey = 'saved_password'; // Contraseña cifrada para biometría

  // Guardar token de autenticación
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // Obtener token de autenticación
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Guardar datos del usuario
  Future<void> saveUser(Usuario usuario) async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = usuario.toJson();
    final userJsonString = jsonEncode(userJson);

    print('💾 DEBUG: Guardando usuario en almacenamiento:');
    print('  - Nombre: ${usuario.nombre}');
    print('  - Email: ${usuario.email}');
    print('  - Roles: ${usuario.roles}');
    print('  - JSON: $userJsonString');

    await prefs.setString(_userKey, userJsonString);
    print('✅ Usuario guardado exitosamente');
  }

  // Obtener datos del usuario
  Future<Usuario?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);

    print('📖 DEBUG: Recuperando usuario del almacenamiento:');
    print('  - JSON encontrado: $userJson');

    if (userJson != null) {
      try {
        final userMap = jsonDecode(userJson) as Map<String, dynamic>;
        // print('  - Map decodificado: $userMap');

        final usuario = Usuario.fromJson(userMap);
        print('  - Usuario recuperado:');
        print('    - Nombre: ${usuario.nombre}');
        print('    - Email: ${usuario.email}');
        print('    - Roles: ${usuario.roles}');

        return usuario;
      } catch (e) {
        print('❌ Error al parsear usuario desde almacenamiento: $e');
        return null;
      }
    }
    print('⚠️ No se encontró usuario en almacenamiento');
    return null;
  }

  // Guardar preferencia "Recordarme"
  Future<void> setRememberMe(bool rememberMe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, rememberMe);
  }

  // Obtener preferencia "Recordarme"
  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  // Guardar fecha de último login
  Future<void> setLastLogin(DateTime dateTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLoginKey, dateTime.toIso8601String());
  }

  // Obtener fecha de último login
  Future<DateTime?> getLastLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(_lastLoginKey);
    if (dateString != null) {
      try {
        return DateTime.parse(dateString);
      } catch (e) {
        print('Error al parsear fecha de último login: $e');
        return null;
      }
    }
    return null;
  }

  // Verificar si hay una sesión válida
  Future<bool> hasValidSession() async {
    final token = await getToken();
    final user = await getUser();
    return token != null && user != null;
  }

  // Guardar identificador (email o teléfono) del usuario para login rápido
  Future<void> setSavedIdentifier(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedIdentifierKey, identifier);
  }

  // Obtener identificador guardado
  Future<String?> getSavedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedIdentifierKey);
  }

  // Limpiar identificador guardado
  Future<void> clearSavedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedIdentifierKey);
  }

  // Guardar estadísticas del dashboard
  Future<void> saveDashboardStatistics(DashboardStatistics statistics) async {
    final prefs = await SharedPreferences.getInstance();
    final statsJson = statistics.toJson();
    final statsJsonString = jsonEncode(statsJson);

    print('💾 DEBUG: Guardando estadísticas del dashboard');
    print('  - Estadísticas: $statistics');

    await prefs.setString(_dashboardStatsKey, statsJsonString);
    print('✅ Estadísticas del dashboard guardadas exitosamente');
  }

  // Obtener estadísticas del dashboard
  Future<DashboardStatistics?> getDashboardStatistics() async {
    final prefs = await SharedPreferences.getInstance();
    final statsJson = prefs.getString(_dashboardStatsKey);

    if (statsJson != null) {
      try {
        final statsMap = jsonDecode(statsJson) as Map<String, dynamic>;
        final statistics = DashboardStatistics.fromJson(statsMap);
        print('📖 DEBUG: Estadísticas del dashboard recuperadas');
        return statistics;
      } catch (e) {
        print('❌ Error al parsear estadísticas desde almacenamiento: $e');
        return null;
      }
    }
    print('ℹ️ No se encontraron estadísticas del dashboard en almacenamiento');
    return null;
  }

  // Limpiar toda la sesión
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_lastLoginKey);
    await prefs.remove(_dashboardStatsKey);

    // No limpiar rememberMe para mantener la preferencia del usuario
    // await prefs.remove(_rememberMeKey);

    print('🧹 Sesión limpiada completamente');
  }

  // Limpiar solo los datos del usuario (para sesiones parciales)
  Future<void> clearUserOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);

    print('🧹 Datos del usuario limpiados (sesión parcial)');
  }

  // Obtener información de la sesión
  Future<Map<String, dynamic>> getSessionInfo() async {
    final token = await getToken();
    final user = await getUser();
    final rememberMe = await getRememberMe();
    final lastLogin = await getLastLogin();

    return {
      'hasToken': token != null,
      'hasUser': user != null,
      'rememberMe': rememberMe,
      'lastLogin': lastLogin?.toIso8601String(),
      'user': user?.toJson(),
    };
  }

  /// Establecer flag de re-autenticación requerida
  Future<void> setRequiresReauth(bool required) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_requiresReauthKey, required);
    print('🔐 Flag requiresReauth establecido en: $required');
  }

  /// Obtener flag de re-autenticación requerida
  Future<bool> getRequiresReauth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_requiresReauthKey) ?? false;
  }

  /// Limpiar flag de re-autenticación
  Future<void> clearRequiresReauth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_requiresReauthKey);
    print('🔐 Flag requiresReauth eliminado');
  }

  // ========== Métodos de Autenticación Biométrica ==========

  /// Guardar preferencia de autenticación biométrica
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
    print('👆 Autenticación biométrica ${enabled ? "activada" : "desactivada"}');
  }

  /// Obtener preferencia de autenticación biométrica
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  /// Guardar contraseña (encriptada) para uso con biometría
  /// NOTA: En producción, usar una librería de encriptación robusta
  Future<void> saveBiometricPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    // En producción, encriptar la contraseña antes de guardarla
    // Por ahora la guardamos en base64 para ofuscación básica
    final encoded = base64Encode(utf8.encode(password));
    await prefs.setString(_savedPasswordKey, encoded);
    print('🔐 Contraseña guardada para biometría');
  }

  /// Obtener contraseña guardada para biometría
  Future<String?> getBiometricPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_savedPasswordKey);
    if (encoded != null) {
      try {
        // Decodificar la contraseña
        final decoded = utf8.decode(base64Decode(encoded));
        return decoded;
      } catch (e) {
        print('❌ Error al decodificar contraseña: $e');
        return null;
      }
    }
    return null;
  }

  /// Limpiar datos de autenticación biométrica
  Future<void> clearBiometricData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricEnabledKey);
    await prefs.remove(_savedPasswordKey);
    print('🧹 Datos de autenticación biométrica eliminados');
  }

  /// Verificar si hay datos de biometría guardados
  Future<bool> hasBiometricData() async {
    final enabled = await isBiometricEnabled();
    final password = await getBiometricPassword();
    final identifier = await getSavedIdentifier();
    return enabled && password != null && identifier != null;
  }
}
