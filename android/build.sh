#!/bin/bash

echo "📱 Сборка APK без скачивания с интернета..."

# 1. Установить Gradle если нужно
if ! command -v gradle &> /dev/null; then
    echo "📥 Установка Gradle..."
    brew install gradle
fi

# 2. Очистить
echo "🧹 Очистка..."
flutter clean
rm -rf android/build android/.gradle

# 3. Переустановить зависимости Flutter
echo "📦 Зависимости Flutter..."
flutter pub get

# 4. Собрать через Gradle напрямую
echo "🔨 Сборка APK через Gradle..."
cd android
gradle assembleRelease
cd ..

# 5. Показать результат
echo ""
echo "✅ ГОТОВО!"
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    ls -lh build/app/outputs/flutter-apk/app-release.apk
else
    echo "⚠️ APK не найден, проверьте ошибки выше"
fi
