# Configuración del Script de Build para iOS

Este script carga las variables del archivo `.env` durante el build de iOS para evitar tener las API keys hardcodeadas.

## Configuración en Xcode (Solo necesitas hacer esto UNA VEZ)

### Opción 1: Usando Xcode UI

1. **Abre el proyecto en Xcode:**
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Selecciona el target "Runner"** en el navegador del proyecto (panel izquierdo)

3. **Ve a "Build Phases"** (pestaña superior)

4. **Click en el botón "+"** y selecciona **"New Run Script Phase"**

5. **Arrastra la nueva fase** para que esté ANTES de "Compile Sources"

6. **Agrega el siguiente script:**
   ```bash
   "${SRCROOT}/Scripts/load_env.sh"
   ```

7. **Nombra la fase:** "Load Environment Variables"

8. **Guarda y compila** el proyecto

### Opción 2: Configuración Manual Rápida

Si prefieres, puedes ejecutar este comando que modifica el archivo `project.pbxproj` directamente:

```bash
# NOTA: Crea un backup antes de ejecutar esto
# (Esto requiere un script adicional que podemos crear si lo necesitas)
```

## Verificación

Para verificar que funciona:

1. Limpia el build: `Product → Clean Build Folder` (Cmd + Shift + K)
2. Compila: `Product → Build` (Cmd + B)
3. Verifica en los logs de build que aparece:
   ```
   📖 Leyendo configuración desde .env...
   ✅ API Key encontrada: AIzaSyDu3G...
   ✅ Archivo de configuración generado
   ```

## Solución de Problemas

### Error: "No se encontró el archivo .env"
- Verifica que el archivo `.env` existe en la raíz del proyecto (2 niveles arriba de `ios/`)
- La ruta debe ser: `cobradorlp/.env`

### Error: "Permission denied"
- Ejecuta: `chmod +x ios/Scripts/load_env.sh`

### La API key no se carga
- Verifica que `.env` contiene la línea: `GOOGLE_MAPS_API_KEY_IOS=tu_api_key`
- Verifica que no hay espacios alrededor del `=`
- Limpia el build folder y vuelve a compilar

## Cómo Funciona

1. Durante el build de Xcode, se ejecuta `load_env.sh`
2. El script lee `GOOGLE_MAPS_API_KEY_IOS` del archivo `.env`
3. Genera un archivo `Flutter/Generated.xcconfig` con la variable
4. Xcode usa esta variable en `Info.plist`: `$(GOOGLE_MAPS_API_KEY)`
5. La app se compila con la API key correcta

## Beneficios

- ✅ No hay API keys hardcodeadas en el código
- ✅ El archivo `.env` está en `.gitignore` (no se sube a Git)
- ✅ Cada desarrollador puede tener su propia API key
- ✅ Fácil de cambiar sin recompilar
