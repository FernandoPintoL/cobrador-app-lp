#!/usr/bin/env python3
"""
Script para crear iconos de notificación optimizados desde el icono principal.
Los iconos de notificación en Android se ven mejor con alto contraste.
"""

from PIL import Image, ImageEnhance, ImageOps
import os

# Rutas
input_path = "assets/icons/icon.png"
base_output_dir = "android/app/src/main/res"

# Tamaños para cada densidad de pantalla
sizes = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}

def create_notification_icon(input_image_path, output_path, size):
    """
    Crea un icono de notificación optimizado.

    Args:
        input_image_path: Ruta de la imagen original
        output_path: Ruta donde guardar el icono
        size: Tamaño del icono en píxeles
    """
    try:
        # Abrir la imagen original
        img = Image.open(input_image_path)

        # Convertir a RGBA si no lo está
        if img.mode != 'RGBA':
            img = img.convert('RGBA')

        # Redimensionar manteniendo la proporción
        img.thumbnail((size, size), Image.Resampling.LANCZOS)

        # Crear una nueva imagen del tamaño exacto con fondo transparente
        new_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))

        # Centrar la imagen redimensionada
        offset = ((size - img.size[0]) // 2, (size - img.size[1]) // 2)
        new_img.paste(img, offset, img)

        # Aumentar el contraste para mejor visibilidad
        enhancer = ImageEnhance.Contrast(new_img)
        new_img = enhancer.enhance(1.5)

        # Aumentar el brillo ligeramente
        enhancer = ImageEnhance.Brightness(new_img)
        new_img = enhancer.enhance(1.2)

        # Guardar el icono optimizado
        new_img.save(output_path, 'PNG', optimize=True)
        print(f"✅ Creado: {output_path} ({size}x{size}px)")

    except Exception as e:
        print(f"❌ Error creando {output_path}: {e}")

def main():
    print("🎨 Creando iconos de notificación optimizados...\n")

    # Verificar que existe la imagen original
    if not os.path.exists(input_path):
        print(f"❌ Error: No se encontró el archivo {input_path}")
        return

    # Crear iconos para cada densidad
    for density, size in sizes.items():
        output_dir = os.path.join(base_output_dir, density)

        # Crear el directorio si no existe
        os.makedirs(output_dir, exist_ok=True)

        # Ruta del icono de salida
        output_path = os.path.join(output_dir, "ic_notification.png")

        # Crear el icono
        create_notification_icon(input_path, output_path, size)

    print("\n✅ ¡Todos los iconos de notificación fueron creados exitosamente!")
    print("\n📱 Los iconos están optimizados con:")
    print("   • Alto contraste para mejor visibilidad")
    print("   • Brillo mejorado")
    print("   • Transparencia preservada")
    print("   • Optimización de tamaño de archivo")

if __name__ == "__main__":
    main()
