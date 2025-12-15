import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../datos/modelos/map/location_cluster.dart';
import '../../negocio/providers/auth_provider.dart';
import '../../negocio/providers/manager_provider.dart';
import '../../negocio/providers/map_provider.dart' as mp_provider;
import '../../config/role_colors.dart';
import 'utils/client_data_extractor.dart';
import 'utils/cluster_icon_generator.dart';
import 'widgets/client_details_sheet.dart';
import 'widgets/cluster_people_list.dart';
import 'widgets/map_filters_bar.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  // Controladores y estado del mapa
  GoogleMapController? _mapController;
  LatLng? _myLocation;
  MapType _mapType = MapType.normal;

  // Filtros
  int? _selectedCobradorId;
  String? _statusFilter;
  String? _searchQuery;
  bool _sortByDistance = false;

  // Ubicación inicial (Lima)
  static const LatLng _initialCenter = LatLng(-12.0464, -77.0428);
  static const CameraPosition _initialCamera = CameraPosition(
    target: _initialCenter,
    zoom: 11.5,
  );

  // Cache de iconos
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      _loadCobradores();
    });
  }

  /// Carga los cobradores asignados si el usuario es manager
  void _loadCobradores() {
    final auth = ref.read(authProvider);
    final role = _getUserRole(auth.usuario?.roles ?? []);
    if (role == 'manager') {
      final managerId = auth.usuario!.id.toString();
      ref.read(managerProvider.notifier).cargarCobradoresAsignados(managerId);
    }
  }

  /// Inicializa la ubicación del usuario
  Future<void> _initLocation() async {
    try {
      // Verificar si el servicio de ubicación está habilitado
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        _showLocationServiceDialog();
        return;
      }

      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Manejar permisos denegados
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        _showPermissionDeniedForeverDialog();
        return;
      } else if (permission == LocationPermission.denied) {
        if (!mounted) return;
        _showPermissionDeniedDialog();
        return;
      }

      // Obtener ubicación actual
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() => _myLocation = latLng);

      // Centrar mapa en la ubicación del usuario
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(latLng, 15),
        );
      }
    } catch (e) {
      debugPrint('Error al obtener ubicación: $e');
      if (mounted) {
        _showLocationErrorDialog();
      }
    }
  }

  /// Muestra diálogo cuando el servicio de ubicación está deshabilitado
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Servicio de ubicación deshabilitado'),
        content: const Text(
          'Por favor habilita el servicio de ubicación en la configuración de tu dispositivo para ver tu posición en el mapa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text('Abrir configuración'),
          ),
        ],
      ),
    );
  }

  /// Muestra diálogo cuando los permisos fueron denegados permanentemente
  void _showPermissionDeniedForeverDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisos de ubicación denegados'),
        content: const Text(
          'Los permisos de ubicación fueron denegados permanentemente. Para habilitar tu ubicación en el mapa, debes otorgar permisos manualmente en la configuración de la aplicación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Abrir configuración'),
          ),
        ],
      ),
    );
  }

  /// Muestra diálogo cuando los permisos fueron denegados
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisos de ubicación necesarios'),
        content: const Text(
          'Esta aplicación necesita acceso a tu ubicación para mostrarte en el mapa y encontrar clientes cercanos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _initLocation();
            },
            child: const Text('Intentar de nuevo'),
          ),
        ],
      ),
    );
  }

  /// Muestra diálogo cuando hay un error al obtener la ubicación
  void _showLocationErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error al obtener ubicación'),
        content: const Text(
          'No se pudo obtener tu ubicación actual. Por favor verifica tu conexión y los permisos de ubicación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _initLocation();
            },
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  /// Refresca los datos del mapa invalidando el provider
  Future<void> _refreshData() async {
    // Invalidar el provider para forzar una nueva carga de datos
    ref.invalidate(mp_provider.mapLocationClustersProvider);

    // Esperar un momento para que se complete la recarga
    await Future.delayed(const Duration(milliseconds: 500));

    // Mostrar mensaje de confirmación
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos actualizados'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Obtiene el rol del usuario
  String _getUserRole(List<String> roles) {
    final lowered = roles.map((e) => e.toLowerCase()).toList();
    if (lowered.contains('admin')) return 'admin';
    if (lowered.contains('manager')) return 'manager';
    if (lowered.contains('cobrador')) return 'cobrador';
    return lowered.isNotEmpty ? lowered.first : '';
  }

  /// Calcula la distancia desde la ubicación actual al punto dado
  String? _calculateDistance(double lat, double lng) {
    if (_myLocation == null) return null;

    final distanceInMeters = Geolocator.distanceBetween(
      _myLocation!.latitude,
      _myLocation!.longitude,
      lat,
      lng,
    );

    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()}m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Calcula la distancia en metros (para ordenamiento)
  double? _calculateDistanceInMeters(double lat, double lng) {
    if (_myLocation == null) return null;

    return Geolocator.distanceBetween(
      _myLocation!.latitude,
      _myLocation!.longitude,
      lat,
      lng,
    );
  }

  /// Ordena los clusters por distancia si está activado
  List<LocationCluster> _sortClusters(List<LocationCluster> clusters) {
    if (!_sortByDistance || _myLocation == null) {
      return clusters;
    }

    final sortedClusters = List<LocationCluster>.from(clusters);
    sortedClusters.sort((a, b) {
      final distA = _calculateDistanceInMeters(
        a.location.latitude,
        a.location.longitude,
      );
      final distB = _calculateDistanceInMeters(
        b.location.latitude,
        b.location.longitude,
      );

      if (distA == null && distB == null) return 0;
      if (distA == null) return 1;
      if (distB == null) return -1;
      return distA.compareTo(distB);
    });

    return sortedClusters;
  }

  /// Construye los marcadores desde los clusters
  /// UN MARCADOR POR CLUSTER (casa), no por persona
  Future<Set<Marker>> _buildMarkers(List<LocationCluster> clusters) async {
    final markers = <Marker>{};

    for (final cluster in clusters) {
      final lat = cluster.location.latitude;
      final lng = cluster.location.longitude;
      final peopleCount = cluster.people.length;
      final clusterStatus = cluster.clusterStatus;

      // Calcular distancia
      final distance = _calculateDistance(lat, lng);

      // Color basado en el estado del cluster
      final color = _getColorForClusterStatus(clusterStatus);

      // Determinar icono basado en número de personas
      BitmapDescriptor icon;
      if (peopleCount == 1) {
        // UN CLIENTE: mostrar sus datos personales
        final person = cluster.people.first;
        final paidToday = ClientDataExtractor.extractPaidToday(person);
        final pagoLabel = ClientDataExtractor.labelForPaidToday(paidToday);
        final personColor = ClientDataExtractor.colorForPaidToday(paidToday);

        // Información de próximo pago
        final nextInfo = ClientDataExtractor.extractNextPaymentInfo(person);
        final amount = nextInfo['amount'] as double?;
        final installment = nextInfo['installment'] as int?;

        String? secondLine;
        if (installment != null && amount != null) {
          secondLine =
              'Cuota #$installment · ${ClientDataExtractor.formatSoles(amount)}';
        } else if (installment != null) {
          secondLine = 'Cuota #$installment';
        } else if (amount != null) {
          secondLine = ClientDataExtractor.formatSoles(amount);
        }

        if (secondLine != null) {
          final cacheKey = '$paidToday|$secondLine';
          if (_markerIconCache.containsKey(cacheKey)) {
            icon = _markerIconCache[cacheKey]!;
          } else {
            icon = await ClusterIconGenerator.generateMarkerIcon(
              pagoLabel,
              personColor,
              line2: secondLine,
            );
            _markerIconCache[cacheKey] = icon;
          }
        } else {
          icon = await ClusterIconGenerator.generateMarkerIcon(
            pagoLabel,
            personColor,
          );
        }
      } else {
        // MÚLTIPLES CLIENTES: mostrar contador
        icon = await ClusterIconGenerator.generateClusterIcon(
          peopleCount,
          clusterStatus,
          color,
        );
      }

      // Crear snippet con dirección y distancia
      String snippet = cluster.location.address;
      if (distance != null) {
        snippet = '$snippet\n📍 A $distance';
      }

      markers.add(
        Marker(
          markerId: MarkerId('cluster_${cluster.clusterId}'),
          position: LatLng(lat, lng),
          icon: icon,
          infoWindow: InfoWindow(
            title: peopleCount == 1
                ? cluster.people.first.name
                : '$peopleCount personas',
            snippet: snippet,
            onTap: () => _showClusterModal(context, cluster),
          ),
          onTap: () => _showClusterModal(context, cluster),
        ),
      );
    }

    return markers;
  }

  /// Obtiene el color para el estado del cluster
  Color _getColorForClusterStatus(String status) {
    switch (status.toLowerCase()) {
      case 'overdue':
        return Colors.red.shade400;
      case 'pending':
        return Colors.amber.shade700;
      case 'paid':
        return Colors.green.shade600;
      default:
        return Colors.blue.shade400;
    }
  }

  /// Muestra el modal apropiado según el número de personas
  /// Si hay 1 persona: muestra detalles directamente
  /// Si hay múltiples: muestra listado para seleccionar
  void _showClusterModal(BuildContext context, LocationCluster cluster) {
    final location = LatLng(cluster.location.latitude, cluster.location.longitude);
    if (cluster.people.length == 1) {
      // Caso: 1 persona → mostrar detalles directamente
      _showClientDetailsSheet(context, cluster.people.first, location: location);
    } else {
      // Caso: múltiples personas → mostrar listado
      _showClusterPeopleListSheet(context, cluster, location);
    }
  }

  /// Muestra el modal con listado de personas en el cluster
  void _showClusterPeopleListSheet(
    BuildContext context,
    LocationCluster cluster,
    LatLng location,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ClusterPeopleList(
              cluster: cluster,
              onPersonSelected: (person) {
                Navigator.pop(context); // Cerrar listado
                _showClientDetailsSheet(context, person, location: location);
              },
            ),
          ),
        );
      },
    );
  }

  /// Muestra el modal con detalles del cliente
  void _showClientDetailsSheet(BuildContext context, ClusterPerson person, {LatLng? location}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (_, controller) => ClientDetailsSheet(
                  person: person,
                  scrollController: controller,
                  latitude: location?.latitude,
                  longitude: location?.longitude,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.usuario;
    final role = _getUserRole(user?.roles ?? []);
    final isAdminOrManager = role == 'admin' || role == 'manager';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Watchear el provider de clusters
    final clustersAsync = ref.watch(
      mp_provider.mapLocationClustersProvider(
        mp_provider.MapClusterQuery(
          search: _searchQuery,
          status: _statusFilter,
          cobradorId: _selectedCobradorId,
        ),
      ),
    );

    // Color principal basado en rol
    final primaryColor = role == 'manager'
        ? RoleColors.managerPrimary
        : RoleColors.cobradorPrimary;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      primaryColor.withValues(alpha: 0.2),
                      primaryColor.withValues(alpha: 0.1),
                    ]
                  : [
                      primaryColor.withValues(alpha: 0.15),
                      primaryColor.withValues(alpha: 0.08),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.2),
                        primaryColor.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.map_rounded,
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Mapa de Clientes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      clustersAsync.whenOrNull(
                        data: (clusters) {
                          final totalClientes = clusters.fold<int>(
                            0,
                            (sum, cluster) => sum + cluster.people.length,
                          );
                          return Text(
                            '$totalClientes ${totalClientes == 1 ? 'cliente' : 'clientes'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ) ?? const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Botón de refresh
              IconButton(
                onPressed: _refreshData,
                icon: Icon(Icons.refresh_rounded, color: primaryColor),
                tooltip: 'Actualizar datos',
              ),
              if (isAdminOrManager) _buildCobradorSelector(),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withValues(alpha: 0.15),
                      primaryColor.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _mapType = _mapType == MapType.satellite
                          ? MapType.normal
                          : MapType.satellite;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        _mapType == MapType.satellite
                            ? Icons.map_rounded
                            : Icons.satellite_alt_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: clustersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => _buildErrorView(e, context),
        data: (clusters) => _buildMapView(clusters, context),
      ),
      floatingActionButton: _MapSpeedDial(
        primaryColor: primaryColor,
        onCenterMap: _initLocation,
        onToggleMapType: () => setState(() {
          _mapType = _mapType == MapType.satellite
              ? MapType.normal
              : MapType.satellite;
        }),
        onPlanRoute: () {
          // TODO: Navegar a pantalla de planificación de rutas
          Navigator.pushNamed(context, '/route-planner');
        },
      ),
    );
  }

  Widget _buildMapView(List<LocationCluster> clusters, BuildContext context) {
    // Aplicar ordenamiento por distancia si está activado
    final sortedClusters = _sortClusters(clusters);

    return Column(
      children: [
        // Búsqueda
        ClusterSearchBar(
          onSearch: (query) => setState(() => _searchQuery = query.isEmpty ? null : query),
        ),

        // Filtros de estado y ordenamiento
        Row(
          children: [
            Expanded(
              child: MapStatusFiltersBar(
                selectedStatus: _statusFilter,
                onStatusChanged: (status) => setState(() => _statusFilter = status),
              ),
            ),
            // Botón de ordenar por distancia
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _myLocation == null
                      ? null
                      : () => setState(() => _sortByDistance = !_sortByDistance),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _sortByDistance
                          ? Colors.blue
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _sortByDistance
                          ? [
                              BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      Icons.near_me_rounded,
                      color: _sortByDistance ? Colors.white : Colors.grey.shade600,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Estadísticas (mostrar solo si hay un cluster seleccionado o el primero)
        if (sortedClusters.isNotEmpty)
          ClusterStatsBar(cluster: sortedClusters.first),

        // Mapa
        Expanded(
          child: Stack(
            children: [
              FutureBuilder<Set<Marker>>(
                future: _buildMarkers(sortedClusters),
                builder: (context, snapshot) {
                  // Mostrar indicador de carga mientras se construyen los markers
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Stack(
                      children: [
                        GoogleMap(
                          mapType: _mapType,
                          initialCameraPosition: _initialCamera,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                          zoomControlsEnabled: false,
                          markers: const {},
                          onMapCreated: (controller) {
                            _mapController = controller;
                          },
                        ),
                        Container(
                          color: Colors.black12,
                          child: const Center(
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('Cargando ubicaciones...'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  final markers = snapshot.data ?? {};
                  return GoogleMap(
                    mapType: _mapType,
                    initialCameraPosition: _initialCamera,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    markers: markers,
                    onMapCreated: (controller) async {
                      _mapController = controller;
                      if (_myLocation != null) {
                        await controller.animateCamera(
                          CameraUpdate.newLatLngZoom(_myLocation!, 15),
                        );
                      } else if (markers.isNotEmpty) {
                        final first = markers.first.position;
                        await controller.animateCamera(
                          CameraUpdate.newLatLngZoom(first, 13),
                        );
                      }
                    },
                  );
                },
              ),
              if (sortedClusters.isEmpty)
                _buildEmptyView()
              else if (sortedClusters.length == 1 && sortedClusters.first.people.isEmpty)
                _buildEmptyView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyView() {
    return Container(
      color: Colors.white.withOpacity(0.9),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_pin_circle_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay clientes en el mapa',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'No se encontraron clientes con ubicaciones asignadas. '
                  'Asegúrate de que los clientes tengan direcciones configuradas.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _initLocation(),
                      icon: const Icon(Icons.my_location),
                      label: const Text('Mi ubicación'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refrescar'),
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

  Widget _buildErrorView(dynamic error, BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 8),
          Text(
            'Error al cargar datos:\n$error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() {}),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildCobradorSelector() {
    final managerState = ref.watch(managerProvider);
    final cobradores = managerState.cobradoresAsignados;

    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            hint: const Text('Filtrar por cobrador'),
            value: _selectedCobradorId,
            onChanged: (v) => setState(() => _selectedCobradorId = v),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
              ...cobradores.map(
                (u) => DropdownMenuItem<int?>(
                  value: u.id.toInt(),
                  child: Text(u.nombre.isNotEmpty ? u.nombre : 'Usuario ${u.id}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    ClusterIconGenerator.clearCache();
    super.dispose();
  }
}

/// Speed Dial FAB moderno para acciones rápidas del mapa
class _MapSpeedDial extends StatefulWidget {
  final Color primaryColor;
  final VoidCallback onCenterMap;
  final VoidCallback onToggleMapType;
  final VoidCallback onPlanRoute;

  const _MapSpeedDial({
    required this.primaryColor,
    required this.onCenterMap,
    required this.onToggleMapType,
    required this.onPlanRoute,
  });

  @override
  State<_MapSpeedDial> createState() => _MapSpeedDialState();
}

class _MapSpeedDialState extends State<_MapSpeedDial>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Acciones secundarias
        if (_isExpanded) ...[
          _buildSpeedDialOption(
            icon: Icons.route_rounded,
            label: 'Planificar ruta',
            color: Colors.green,
            isDark: isDark,
            onTap: () {
              _toggleExpand();
              widget.onPlanRoute();
            },
          ),
          const SizedBox(height: 12),
          _buildSpeedDialOption(
            icon: Icons.my_location_rounded,
            label: 'Mi ubicación',
            color: Colors.blue,
            isDark: isDark,
            onTap: () {
              _toggleExpand();
              widget.onCenterMap();
            },
          ),
          const SizedBox(height: 12),
          _buildSpeedDialOption(
            icon: Icons.layers_rounded,
            label: 'Cambiar vista',
            color: Colors.purple,
            isDark: isDark,
            onTap: () {
              _toggleExpand();
              widget.onToggleMapType();
            },
          ),
          const SizedBox(height: 16),
        ],

        // Botón principal
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.primaryColor,
                widget.primaryColor.withValues(alpha: 0.8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.primaryColor.withValues(alpha: 0.4),
                blurRadius: _isExpanded ? 20 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpand,
              customBorder: const CircleBorder(),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: AnimatedRotation(
                  turns: _isExpanded ? 0.125 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _isExpanded ? Icons.close_rounded : Icons.add_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedDialOption({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return FadeTransition(
      opacity: _expandAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5),
          end: Offset.zero,
        ).animate(_expandAnimation),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade800
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Button
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color,
                    color.withValues(alpha: 0.8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
