import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import '../../ui/utilidades/image_utils.dart';
import '../../ui/utilidades/phone_utils.dart';
import '../../datos/modelos/usuario.dart';
import '../../datos/api_services/user_api_service.dart';
import '../../datos/api_services/api_service.dart';
import '../../negocio/providers/user_management_provider.dart';
import '../../negocio/providers/auth_provider.dart';
import '../../config/role_colors.dart';
import 'location_picker_screen.dart';
import '../widgets/camera/camera_with_document_detection_screen.dart';
import '../widgets/camera/camera_with_face_detection_screen.dart';
import '../widgets/adaptive_form_app_bar.dart';

class ClienteFormScreen extends ConsumerStatefulWidget {
  final Usuario? cliente; // null para crear, con datos para editar
  final VoidCallback? onClienteSaved;
  final VoidCallback? onClienteCreated;
  final String? initialName;

  const ClienteFormScreen({
    super.key,
    this.cliente,
    this.onClienteSaved,
    this.onClienteCreated,
    this.initialName,
  });

  @override
  ConsumerState<ClienteFormScreen> createState() =>
      _ManagerClienteFormScreenState();
}

class _ManagerClienteFormScreenState extends ConsumerState<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController(); // Dirección principal
  final _descripcionCasaController =
      TextEditingController(); // Descripción de la casa
  final _contrasenaController = TextEditingController();
  final _ciController = TextEditingController();

  bool _esEdicion = false;
  bool _isLoading = false;

  // Variables para errores de campo específicos
  String? _nombreError;
  String? _apellidosError;
  String? _telefonoError;
  String? _direccionError;
  String? _descripcionCasaError;
  String? _ciError;

  // Variables para ubicación GPS
  double? _latitud;
  double? _longitud;
  bool _ubicacionObtenida = false;
  String _tipoUbicacion = ''; // 'actual' o 'mapa'

  // Imágenes requeridas de CI y opcional foto de perfil
  File? _idFront;
  File? _idBack;
  File? _profileImage;
  final _picker = ImagePicker();

  // Estados de carga para procesamiento de imágenes
  bool _isProcessingIdFront = false;
  bool _isProcessingIdBack = false;
  bool _isProcessingProfile = false;

  // URLs existentes (modo edición)
  String? _idFrontUrl;
  String? _idBackUrl;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _esEdicion = widget.cliente != null;

    if (_esEdicion) {
      // Usar ApiService para construir correctamente la URL de la imagen de perfil
      final apiService = ApiService();

      // Si hay una imagen de perfil, construir la URL correcta
      if (widget.cliente!.profileImage.isNotEmpty) {
        _profileImageUrl = apiService.getProfileImageUrl(
          widget.cliente!.profileImage,
        );
        debugPrint('🖼️ URL de perfil construida: $_profileImageUrl');
      } else {
        _profileImageUrl = null;
        debugPrint('⚠️ No hay imagen de perfil para el cliente');
      }

      debugPrint(
        'Cargando fotos existentes para el cliente: ${widget.cliente!.nombre}',
      );
      _cargarFotosExistentes(widget.cliente!.id);

      // Separar nombre completo en nombre y apellidos
      final nombreCompleto = widget.cliente!.nombre.trim();
      final partesNombre = nombreCompleto.split(' ');
      if (partesNombre.isNotEmpty) {
        _nombreController.text = partesNombre.first;
        if (partesNombre.length > 1) {
          _apellidosController.text = partesNombre.sublist(1).join(' ');
        }
      }

      _telefonoController.text = widget.cliente!.telefono;

      // Separar dirección existente en dos campos
      final direccionCompleta = widget.cliente!.direccion;
      _parsearDireccionExistente(direccionCompleta);

      _ciController.text = widget.cliente!.ci;

      // Cargar ubicación si existe
      if (widget.cliente!.latitud != null && widget.cliente!.longitud != null) {
        _latitud = widget.cliente!.latitud;
        _longitud = widget.cliente!.longitud;
        _ubicacionObtenida = true;
        _tipoUbicacion = 'existente';
      }
    } else if (widget.initialName != null &&
        widget.initialName!.trim().isNotEmpty) {
      // Separar nombre inicial en nombre y apellidos si es posible
      final nombreCompleto = widget.initialName!.trim();
      final partesNombre = nombreCompleto.split(' ');
      if (partesNombre.isNotEmpty) {
        _nombreController.text = partesNombre.first;
        if (partesNombre.length > 1) {
          _apellidosController.text = partesNombre.sublist(1).join(' ');
        }
      }
    }

    // Intento automático de obtener ubicación actual al abrir (solo en creación)
    if (!_esEdicion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoObtenerUbicacionActual();
      });
    }
  }

  String _getTipoUbicacionTexto() {
    switch (_tipoUbicacion) {
      case 'actual':
        return 'Ubicación actual obtenida';
      case 'mapa':
        return 'Ubicación seleccionada en mapa';
      case 'existente':
        return 'Ubicación existente';
      default:
        return 'Ubicación GPS obtenida';
    }
  }

  void _parsearDireccionExistente(String direccionCompleta) {
    if (direccionCompleta.isEmpty) {
      return;
    }

    // Intentar separar la dirección en dirección principal y descripción de casa
    // Buscar patrones comunes de separación como comas, punto y coma, o palabras clave
    final separadores = [
      ', casa ',
      ', Casa ',
      '; casa ',
      '; Casa ',
      ' - casa ',
      ' - Casa ',
      ' casa ',
      ' Casa ',
    ];

    String direccionPrincipal = direccionCompleta;
    String descripcionCasa = '';

    for (final separador in separadores) {
      if (direccionCompleta.contains(separador)) {
        final partes = direccionCompleta.split(separador);
        if (partes.length >= 2) {
          direccionPrincipal = partes[0].trim();
          descripcionCasa = partes.sublist(1).join(separador).trim();
          break;
        }
      }
    }

    // Si no encontramos un separador obvio, buscar después de números/direcciones comunes
    if (descripcionCasa.isEmpty) {
      final regex = RegExp(
        r'^([^,]*(?:av\.|avenida|calle|c\.|carrera|cr\.|diagonal|diag\.|transversal|tv\.|mz\.|manzana|lote|lt\.)[^,]*(?:\d+[^,]*)?),\s*(.+)$',
        caseSensitive: false,
      );
      final match = regex.firstMatch(direccionCompleta);
      if (match != null) {
        direccionPrincipal = match.group(1)?.trim() ?? direccionCompleta;
        descripcionCasa = match.group(2)?.trim() ?? '';
      }
    }

    // Si aún no hay descripción, usar toda la dirección como principal
    _direccionController.text = direccionPrincipal;
    _descripcionCasaController.text = descripcionCasa;
  }

  void _limpiarErroresCampos() {
    setState(() {
      _nombreError = null;
      _apellidosError = null;
      _telefonoError = null;
      _direccionError = null;
      _descripcionCasaError = null;
      _ciError = null;
    });
  }

  String _obtenerDireccionCompleta() {
    final direccion = _direccionController.text.trim();
    final descripcion = _descripcionCasaController.text.trim();

    if (direccion.isEmpty && descripcion.isEmpty) {
      return '';
    } else if (direccion.isEmpty) {
      return descripcion;
    } else if (descripcion.isEmpty) {
      return direccion;
    } else {
      // Combinar con una coma y espacio
      return '$direccion, $descripcion';
    }
  }

  void _procesarErroresCampos(Map<String, dynamic>? errorsMap) {
    if (errorsMap == null || errorsMap.isEmpty) return;

    setState(() {
      // Limpiar errores previos
      _nombreError = null;
      _apellidosError = null;
      _telefonoError = null;
      _direccionError = null;
      _ciError = null;

      // Procesar errores del backend
      // El formato es: { "field": ["error message 1", "error message 2"] }
      errorsMap.forEach((field, messages) {
        if (messages is List && messages.isNotEmpty) {
          final errorMessage = messages.first.toString();
          final fieldLower = field.toLowerCase();

          // Mapear campos del backend a variables de error
          if (fieldLower == 'name' || fieldLower == 'nombre') {
            _nombreError = errorMessage;
            _apellidosError = errorMessage; // Aplicar también a apellidos
          } else if (fieldLower == 'phone' || fieldLower == 'telefono' || fieldLower == 'teléfono') {
            _telefonoError = errorMessage;
          } else if (fieldLower == 'address' || fieldLower == 'direccion' || fieldLower == 'dirección') {
            _direccionError = errorMessage;
          } else if (fieldLower == 'descripcion' || fieldLower == 'descripción' ||
                     fieldLower == 'casa' || fieldLower == 'características') {
            _descripcionCasaError = errorMessage;
          } else if (fieldLower == 'ci' || fieldLower == 'cedula' || fieldLower == 'cédula') {
            _ciError = errorMessage;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _descripcionCasaController.dispose();
    _contrasenaController.dispose();
    _ciController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AdaptiveFormAppBar(
        title: _esEdicion ? 'Editar Cliente' : 'Crear Cliente',
        showDelete: _esEdicion,
        onDelete: _confirmarEliminarCliente,
        customColor: RoleColors.managerPrimary,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      RoleColors.managerPrimary,
                    ),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Procesando, por favor espera...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                    ? [
                        colorScheme.background,
                        colorScheme.surface,
                      ]
                    : [
                        Colors.grey.shade50,
                        Colors.white,
                      ],
                ),
              ),
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: isDark ? 2 : 8,
                      shadowColor: isDark
                        ? Colors.transparent
                        : Colors.blue.withOpacity(0.2),
                      surfaceTintColor: isDark
                        ? colorScheme.primaryContainer
                        : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: isDark
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Colors.blue.shade50.withOpacity(0.3),
                                ],
                              ),
                        ),
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.shade400,
                                        Colors.blue.shade600,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Información Personal',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Campo de Nombre
                            TextFormField(
                              controller: _nombreController,
                              decoration: InputDecoration(
                                labelText: 'Nombre *',
                                labelStyle: TextStyle(
                                  color: _nombreError != null
                                      ? Colors.red
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                filled: true,
                                fillColor: _nombreError != null
                                    ? Colors.red.shade50
                                    : Colors.blue.shade50.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _nombreError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _nombreError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _nombreError != null
                                        ? Colors.red
                                        : Colors.blue.shade600,
                                    width: 2.5,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2.5,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.person_rounded,
                                  color: _nombreError != null
                                      ? Colors.red
                                      : Colors.blue.shade600,
                                  size: 24,
                                ),
                                errorText: _nombreError,
                              ),
                              inputFormatters: [
                                // Solo letras (incluye acentos), espacios y apóstrofe opcional
                                FilteringTextInputFormatter.allow(
                                  RegExp(r"[A-Za-zÁÉÍÓÚáéíóúÑñÜü\s']"),
                                ),
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El nombre es obligatorio';
                                }
                                if (value.trim().length < 2) {
                                  return 'El nombre debe tener al menos 2 caracteres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            // Campo de Apellidos
                            TextFormField(
                              controller: _apellidosController,
                              decoration: InputDecoration(
                                labelText: 'Apellidos *',
                                labelStyle: TextStyle(
                                  color: _apellidosError != null
                                      ? Colors.red
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                filled: true,
                                fillColor: _apellidosError != null
                                    ? Colors.red.shade50
                                    : Colors.blue.shade50.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _apellidosError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _apellidosError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _apellidosError != null
                                        ? Colors.red
                                        : Colors.blue.shade600,
                                    width: 2.5,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2.5,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.people_rounded,
                                  color: _apellidosError != null
                                      ? Colors.red
                                      : Colors.blue.shade600,
                                  size: 24,
                                ),
                                errorText: _apellidosError,
                              ),
                              inputFormatters: [
                                // Solo letras (incluye acentos), espacios y apóstrofe opcional
                                FilteringTextInputFormatter.allow(
                                  RegExp(r"[A-Za-zÁÉÍÓÚáéíóúÑñÜü\s']"),
                                ),
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Los apellidos son obligatorios';
                                }
                                if (value.trim().length < 2) {
                                  return 'Los apellidos deben tener al menos 2 caracteres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            // CI obligatorio
                            TextFormField(
                              controller: _ciController,
                              decoration: InputDecoration(
                                labelText: 'CI (Cédula de identidad) *',
                                labelStyle: TextStyle(
                                  color: _ciError != null
                                      ? Colors.red
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                filled: true,
                                fillColor: _ciError != null
                                    ? Colors.red.shade50
                                    : Colors.blue.shade50.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _ciError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _ciError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _ciError != null
                                        ? Colors.red
                                        : Colors.blue.shade600,
                                    width: 2.5,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2.5,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.badge_rounded,
                                  color: _ciError != null
                                      ? Colors.red
                                      : Colors.blue.shade600,
                                  size: 24,
                                ),
                                errorText: _ciError,
                              ),
                              inputFormatters: [
                                // Solo letras y números (sin espacios ni símbolos)
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[A-Za-z0-9]'),
                                ),
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El CI es obligatorio';
                                }
                                if (value.trim().length < 5) {
                                  return 'El CI debe tener al menos 5 caracteres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _telefonoController,
                              decoration: InputDecoration(
                                labelText: 'Teléfono *',
                                labelStyle: TextStyle(
                                  color: _telefonoError != null
                                      ? Colors.red
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                filled: true,
                                fillColor: _telefonoError != null
                                    ? Colors.red.shade50
                                    : Colors.blue.shade50.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _telefonoError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _telefonoError != null
                                        ? Colors.red
                                        : Colors.blue.shade200,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _telefonoError != null
                                        ? Colors.red
                                        : Colors.blue.shade600,
                                    width: 2.5,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2.5,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.phone_rounded,
                                  color: _telefonoError != null
                                      ? Colors.red
                                      : Colors.blue.shade600,
                                  size: 24,
                                ),
                                errorText: _telefonoError,
                              ),
                              keyboardType: TextInputType.phone,
                              inputFormatters: [PhoneUtils.inputFormatter()],
                              validator: (value) => PhoneUtils.validatePhone(
                                value,
                                required: true,
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Campo de Dirección Principal
                            TextFormField(
                              controller: _direccionController,
                              decoration: InputDecoration(
                                labelText: 'Dirección *',
                                labelStyle: TextStyle(
                                  color: _direccionError != null
                                      ? Colors.red
                                      : Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                hintText: 'Ej: Av. Principal 123, 4to Anillo',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                filled: true,
                                fillColor: _direccionError != null
                                    ? Colors.red.shade50
                                    : Colors.green.shade50.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _direccionError != null
                                        ? Colors.red
                                        : Colors.green.shade200,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _direccionError != null
                                        ? Colors.red
                                        : Colors.green.shade200,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _direccionError != null
                                        ? Colors.red
                                        : Colors.green.shade600,
                                    width: 2.5,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2.5,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.location_on_rounded,
                                  color: _direccionError != null
                                      ? Colors.red
                                      : Colors.green.shade600,
                                  size: 24,
                                ),
                                errorText: _direccionError,
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Botón para obtener ubicación actual
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: _ubicacionObtenida
                                            ? Colors.green.shade100
                                            : Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.my_location_rounded,
                                          size: 20,
                                          color: _ubicacionObtenida
                                              ? Colors.green.shade700
                                              : Colors.blue.shade700,
                                        ),
                                        onPressed: _obtenerUbicacionActual,
                                        tooltip: 'Obtener mi ubicación actual',
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                      ),
                                    ),
                                    // Botón para seleccionar en mapa
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: _ubicacionObtenida
                                            ? Colors.green.shade100
                                            : Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.map_rounded,
                                          size: 20,
                                          color: _ubicacionObtenida
                                              ? Colors.green.shade700
                                              : Colors.orange.shade700,
                                        ),
                                        onPressed: _obtenerUbicacionGPS,
                                        tooltip: 'Seleccionar en mapa',
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                      ),
                                    ),
                                  ],
                                ),
                                helperText: _ubicacionObtenida
                                    ? '${_getTipoUbicacionTexto()} ✓'
                                    : 'Ingresa la dirección principal (calle, avenida, número)',
                                helperStyle: TextStyle(
                                  color: _ubicacionObtenida
                                      ? Colors.green.shade700
                                      : Colors.grey.shade600,
                                  fontWeight: _ubicacionObtenida
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              maxLines: 2,
                              keyboardType: TextInputType.streetAddress,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'La dirección es obligatoria';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            // Campo de Descripción de la Casa
                            TextFormField(
                              controller: _descripcionCasaController,
                              decoration: InputDecoration(
                                labelText: 'Descripción de la casa',
                                labelStyle: TextStyle(
                                  color: _descripcionCasaError != null
                                      ? Colors.red
                                      : Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                hintText:
                                    'Ej: Casa de dos pisos color azul, portón negro, junto al parque',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                filled: true,
                                fillColor: _descripcionCasaError != null
                                    ? Colors.red.shade50
                                    : Colors.green.shade50.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _descripcionCasaError != null
                                        ? Colors.red
                                        : Colors.green.shade200,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _descripcionCasaError != null
                                        ? Colors.red
                                        : Colors.green.shade200,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _descripcionCasaError != null
                                        ? Colors.red
                                        : Colors.green.shade600,
                                    width: 2.5,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2.5,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.home_rounded,
                                  color: _descripcionCasaError != null
                                      ? Colors.red
                                      : Colors.green.shade600,
                                  size: 24,
                                ),
                                errorText: _descripcionCasaError,
                                helperText:
                                    'Describe características distintivas de la casa para facilitar su ubicación',
                                helperStyle: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              maxLines: 3,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                            ),
                            if (_ubicacionObtenida) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.green.shade50,
                                      Colors.green.shade100.withOpacity(0.5),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.shade300,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade600,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        _tipoUbicacion == 'actual'
                                            ? Icons.my_location_rounded
                                            : _tipoUbicacion == 'mapa'
                                            ? Icons.map_rounded
                                            : Icons.location_on_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Lat: ${_latitud?.toStringAsFixed(4)}, Lng: ${_longitud?.toStringAsFixed(4)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _latitud = null;
                                          _longitud = null;
                                          _ubicacionObtenida = false;
                                          _tipoUbicacion = '';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.red.shade300,
                                            width: 1,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Carga de imágenes de CI y perfil
                    Card(
                      elevation: isDark ? 2 : 8,
                      shadowColor: isDark
                        ? Colors.transparent
                        : Colors.purple.withOpacity(0.2),
                      surfaceTintColor: isDark
                        ? colorScheme.secondaryContainer
                        : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: isDark
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Colors.purple.shade50.withOpacity(0.3),
                                ],
                              ),
                        ),
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.purple.shade400,
                                        Colors.purple.shade600,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.purple.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Documentos de Identidad',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _esEdicion
                                            ? 'Puedes actualizar las fotos del CI si es necesario'
                                            : 'Anverso y Reverso del CI son obligatorios *',
                                        style: TextStyle(
                                          color: _esEdicion
                                              ? Colors.grey[600]
                                              : Colors.purple.shade600,
                                          fontSize: 12,
                                          fontWeight: _esEdicion
                                              ? FontWeight.normal
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _buildImagePicker(
                                  label: 'CI Anverso*',
                                  file: _idFront,
                                  existingUrl: _idFrontUrl,
                                  onTap: () => _pickImage('id_front'),
                                  isProcessing: _isProcessingIdFront,
                                ),
                                const SizedBox(width: 12),
                                _buildImagePicker(
                                  label: 'CI Reverso*',
                                  file: _idBack,
                                  existingUrl: _idBackUrl,
                                  onTap: () => _pickImage('id_back'),
                                  isProcessing: _isProcessingIdBack,
                                ),
                                const SizedBox(width: 12),
                                _buildImagePicker(
                                  label: 'Perfil (Img Referencia)',
                                  file: _profileImage,
                                  existingUrl: _profileImageUrl,
                                  onTap: () => _pickImage('profile'),
                                  isProcessing: _isProcessingProfile,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: Colors.amber.shade800,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Las imágenes deben pesar menos de 1MB. Se comprimen automáticamente.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.amber.shade900,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.cancel_outlined, size: 22),
                              label: const Text(
                                'Cancelar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                side: BorderSide(
                                  color: Colors.grey.shade400,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  RoleColors.managerPrimary,
                                  RoleColors.managerPrimary.withOpacity(0.8),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: RoleColors.managerPrimary.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _guardarCliente,
                              icon: Icon(
                                _esEdicion ? Icons.save_rounded : Icons.person_add_rounded,
                                size: 22,
                              ),
                              label: Text(
                                _esEdicion ? 'Actualizar' : 'Crear Cliente',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ),
    );
  }

  Future<void> _autoObtenerUbicacionActual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      String direccionObtenida = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          direccionObtenida = [
            place.street,
            place.locality,
            place.administrativeArea,
            place.country,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _latitud = position.latitude;
        _longitud = position.longitude;
        _ubicacionObtenida = true;
        _tipoUbicacion = 'actual';
        if (direccionObtenida.isNotEmpty) {
          _direccionController.text = direccionObtenida;
        }
      });
    } catch (_) {
      // silencioso
    }
  }

  Future<void> _obtenerUbicacionActual() async {
    try {
      // Verificar permisos de ubicación
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Los servicios de ubicación están deshabilitados',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permisos de ubicación denegados',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permisos de ubicación denegados permanentemente. Ve a configuración para habilitarlos.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Obteniendo ubicación actual...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );

      // Obtener posición actual
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      // Cerrar diálogo de carga
      if (mounted) Navigator.of(context).pop();

      // Intentar obtener dirección de las coordenadas
      String direccionObtenida = '';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          direccionObtenida =
              [
                    place.street,
                    place.locality,
                    place.administrativeArea,
                    place.country,
                  ]
                  .where((element) => element != null && element.isNotEmpty)
                  .join(', ');
        }
      } catch (e) {
        print('Error al obtener dirección: $e');
      }

      setState(() {
        _latitud = position.latitude;
        _longitud = position.longitude;
        _ubicacionObtenida = true;
        _tipoUbicacion = 'actual';

        // Si se obtuvo una dirección, la usamos; si no, mantenemos la actual
        if (direccionObtenida.isNotEmpty) {
          _direccionController.text = direccionObtenida;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ubicación actual obtenida correctamente\n'
            'Lat: ${position.latitude.toStringAsFixed(4)}\n'
            'Lng: ${position.longitude.toStringAsFixed(4)}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Cerrar diálogo de carga si está abierto
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al obtener ubicación actual: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _obtenerUbicacionGPS() async {
    try {
      // Navegar a la pantalla de selección de ubicación
      // Si hay ubicación guardada (modo edición), mostrarla en el mapa
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (context) => LocationPickerScreen(
            allowSelection: true,
            customTitle: 'Seleccionar ubicación del cliente',
            initialLatitude: _latitud, // Pasar ubicación guardada si existe
            initialLongitude: _longitud, // Pasar ubicación guardada si existe
          ),
        ),
      );

      if (result != null) {
        setState(() {
          _latitud = result['latitud'] as double?;
          _longitud = result['longitud'] as double?;
          _ubicacionObtenida = true;
          _tipoUbicacion = 'mapa';

          // Si viene una dirección, la usamos
          if (result['direccion'] != null &&
              result['direccion'].toString().isNotEmpty) {
            _direccionController.text = result['direccion'] as String;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ubicación seleccionada en mapa correctamente',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al obtener ubicación: $e',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _guardarCliente() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Limpiar errores previos de campos
    _limpiarErroresCampos();

    // Validar fotos requeridas en creación
    if (!_esEdicion) {
      if (_idFront == null || _idBack == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debes subir las fotos del CI (anverso y reverso)',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      if (authState.usuario == null) {
        throw Exception('Usuario no autenticado');
      }

      if (_esEdicion) {
        // Verificar si hay fotos nuevas para actualizar
        bool hayFotosNuevas =
            _idFront != null || _idBack != null || _profileImage != null;

        bool success;
        if (hayFotosNuevas) {
          // Usar el método que actualiza con fotos
          success = await ref
              .read(userManagementProvider.notifier)
              .actualizarUsuarioConFotos(
                id: widget.cliente!.id,
                nombre:
                    '${_nombreController.text.trim()} ${_apellidosController.text.trim()}',
                email: '', // Email vacío para clientes
                ci: _ciController.text.trim(),
                telefono: _telefonoController.text.trim(),
                direccion: _obtenerDireccionCompleta(),
                latitud: _latitud,
                longitud: _longitud,
                idFront: _idFront,
                idBack: _idBack,
                profileImage: _profileImage,
              );
        } else {
          // Usar el método normal sin fotos
          success = await ref
              .read(userManagementProvider.notifier)
              .actualizarUsuario(
                id: widget.cliente!.id,
                nombre:
                    '${_nombreController.text.trim()} ${_apellidosController.text.trim()}',
                email: '', // Email vacío para clientes
                ci: _ciController.text.trim(),
                telefono: _telefonoController.text.trim(),
                direccion: _obtenerDireccionCompleta(),
                latitud: _latitud,
                longitud: _longitud,
              );
        }

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  hayFotosNuevas
                      ? 'Cliente y documentos actualizados exitosamente'
                      : 'Cliente actualizado exitosamente',

                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // Manejar errores
          final state = ref.read(userManagementProvider);

          // Procesar errores de campos específicos
          _procesarErroresCampos(state.fieldErrors);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.error ?? 'Error al actualizar cliente',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return; // No continuar si hubo error
        }
      } else {
        // Crear nuevo cliente con fotos
        final success = await ref
            .read(userManagementProvider.notifier)
            .crearUsuarioConFotos(
              nombre:
                  '${_nombreController.text.trim()} ${_apellidosController.text.trim()}',
              email: '', // Email vacío para clientes
              ci: _ciController.text.trim(),
              roles: ['client'],
              telefono: _telefonoController.text.trim(),
              direccion: _obtenerDireccionCompleta(),
              password: _contrasenaController.text.isNotEmpty
                  ? _contrasenaController.text
                  : null,
              latitud: _latitud,
              longitud: _longitud,
              idFront: _idFront!,
              idBack: _idBack!,
              profileImage: _profileImage,
            );

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cliente creado exitosamente',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // Manejar errores
          final state = ref.read(userManagementProvider);

          // Procesar errores de campos específicos
          _procesarErroresCampos(state.fieldErrors);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.error ?? 'Error al crear cliente',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return; // No continuar si hubo error
        }
      }

      // Llamar callbacks solo si todo fue exitoso
      if (widget.onClienteSaved != null) {
        widget.onClienteSaved!();
      }

      if (mounted) {
        if (!_esEdicion) {
          // Para creación: intentar devolver el cliente creado
          try {
            await Future.delayed(
              const Duration(milliseconds: 200),
            ); // Esperar a que se actualice el estado
            final userState = ref.read(userManagementProvider);
            if (userState.usuarios.isNotEmpty) {
              // Buscar el cliente creado por CI (más confiable que por último)
              final clienteCreado = userState.usuarios.firstWhere(
                (u) => u.ci == _ciController.text.trim(),
                orElse: () => userState.usuarios.last, // Fallback al último
              );
              Navigator.of(context).pop(clienteCreado);
            } else {
              Navigator.of(context).pop(true); // Fallback a boolean
            }
          } catch (e) {
            // Si hay algún error, devolver true como antes
            Navigator.of(context).pop(true);
          }
        } else {
          // Para edición: devolver el cliente actualizado
          Navigator.of(context).pop(widget.cliente);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al ${_esEdicion ? 'actualizar' : 'crear'} cliente: $e',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _confirmarEliminarCliente() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que deseas eliminar permanentemente a ${widget.cliente!.nombre}?\n\n'
          'Esta acción no se puede deshacer y el cliente será eliminado del sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _eliminarCliente();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarCliente() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ref
          .read(userManagementProvider.notifier)
          .eliminarUsuario(widget.cliente!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cliente ${widget.cliente!.nombre} eliminado exitosamente',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );

        if (widget.onClienteSaved != null) {
          widget.onClienteSaved!();
        }

        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al eliminar cliente: $e',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildImagePicker({
    required String label,
    required File? file,
    String? existingUrl,
    required VoidCallback onTap,
    bool isProcessing = false,
  }) {
    final bool hasImage = file != null || (existingUrl != null && existingUrl.isNotEmpty);

    return Expanded(
      child: InkWell(
        onTap: isProcessing ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            gradient: hasImage
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.purple.shade50,
                      Colors.purple.shade100.withOpacity(0.5),
                    ],
                  ),
            border: Border.all(
              color: hasImage
                  ? Colors.purple.shade400
                  : Colors.purple.shade200,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Builder(
                builder: (_) {
                  if (file != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        file,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    );
                  } else if (existingUrl != null && existingUrl.isNotEmpty) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        existingUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    );
                  }
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_photo_alternate_rounded,
                          size: 28,
                          color: Colors.purple.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Badge de edición cuando hay imagen
              if (hasImage && !isProcessing)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade600,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Overlay de carga durante procesamiento
              if (isProcessing)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Procesando...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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

  Future<ImageSource?> _selectImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Cámara'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cargarFotosExistentes(BigInt userId) async {
    try {
      final photos = await UserApiService().listUserPhotos(userId);
      for (final p in photos) {
        final type = p['type']?.toString();
        final url =
            p['url']?.toString() ??
            p['full_url']?.toString() ??
            p['path_url']?.toString();
        if (type == 'id_front' && url != null) {
          _idFrontUrl = url;
        } else if (type == 'id_back' && url != null) {
          _idBackUrl = url;
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      // Silencioso, no bloquear el formulario
      // print('Error al cargar fotos existentes: $e');
    }
  }

  Future<void> _pickImage(String type) async {
    try {
      final source = await _selectImageSource();
      if (source == null) return;

      File? file;

      // Usar cámara in-app con detección automática según el tipo
      if (source == ImageSource.camera) {
        if (!mounted) return;

        // Para CI (anverso y reverso) usar detección de documentos
        if (type == 'id_front' || type == 'id_back') {
          file = await Navigator.of(context).push<File>(
            MaterialPageRoute(
              builder: (context) => CameraWithDocumentDetectionScreen(
                autoCapture: true,
              ),
            ),
          );
        } else {
          // Para foto de perfil usar detección de rostros
          file = await Navigator.of(context).push<File>(
            MaterialPageRoute(
              builder: (context) => CameraWithFaceDetectionScreen(
                autoCapture: true,
              ),
            ),
          );
        }
      } else {
        // Para galería, usar el picker normal
        final XFile? picked = await _picker.pickImage(
          source: source,
          imageQuality: 100,
        );
        if (picked != null) {
          file = File(picked.path);
        }
      }

      if (file == null) return;

      // Activar indicador de carga según el tipo de imagen
      setState(() {
        if (type == 'id_front') {
          _isProcessingIdFront = true;
        } else if (type == 'id_back') {
          _isProcessingIdBack = true;
        } else {
          _isProcessingProfile = true;
        }
      });

      // Comprimir imagen
      file = await ImageUtils.compressToUnder(file, maxBytes: 1024 * 1024);

      setState(() {
        // Guardar archivo e desactivar indicador
        if (type == 'id_front') {
          _idFront = file;
          _isProcessingIdFront = false;
        } else if (type == 'id_back') {
          _idBack = file;
          _isProcessingIdBack = false;
        } else {
          _profileImage = file;
          _isProcessingProfile = false;
        }
      });
    } catch (e) {
      // Desactivar indicadores en caso de error
      setState(() {
        _isProcessingIdFront = false;
        _isProcessingIdBack = false;
        _isProcessingProfile = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo seleccionar la imagen: $e',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
