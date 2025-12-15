#!/bin/sh

# Script para cargar variables de entorno desde .env al build de iOS
# Este script se ejecuta automáticamente durante el build de Xcode

ENV_FILE="${SRCROOT}/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Error: No se encontró el archivo .env en la raíz del proyecto"
  echo "📁 Buscando en: $ENV_FILE"
  exit 1
fi

echo "✅ Cargando variables de entorno desde .env..."

# Leer GOOGLE_MAPS_API_KEY_IOS del archivo .env
GOOGLE_MAPS_API_KEY=$(grep '^GOOGLE_MAPS_API_KEY_IOS=' "$ENV_FILE" | cut -d '=' -f 2- | tr -d '"' | tr -d "'")

if [ -z "$GOOGLE_MAPS_API_KEY" ]; then
  echo "⚠️ Advertencia: GOOGLE_MAPS_API_KEY_IOS no encontrada en .env"
  echo "💡 Agrega: GOOGLE_MAPS_API_KEY_IOS=tu_api_key_aqui"
  exit 1
fi

echo "🔑 API Key encontrada: ${GOOGLE_MAPS_API_KEY:0:10}..."

# Exportar la variable para que Xcode la use
export GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY"

# Escribir en un archivo temporal para que Runner.xcconfig lo lea
echo "GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_API_KEY" > "${SRCROOT}/Flutter/EnvironmentVariables.xcconfig"

echo "✅ Variables de entorno configuradas correctamente"
