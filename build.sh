#!/bin/bash

# Убедитесь, что вы в корневой папке проекта
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Ошибка: запустите скрипт из корневой папки проекта!"
    echo "Текущая папка: $(pwd)"
    exit 1
fi

echo "📱 Сборка APK..."
echo "Папка проекта: $(pwd)"
echo ""

# 1. Исправить версию Gradle (вернуть 8.3.0)
echo "🔧 Исправление версии Gradle..."
sed -i '' 's/gradle-[0-9.]*-all/gradle-8.3.0-all/' android/gradle/wrapper/gradle-wrapper.properties

# 2. Очистить
echo "🧹 Очистка..."
flutter clean
rm -rf android/build android/.gradle

# 3. Зависимости
echo "📦 Загрузка зависимостей..."
flutter pub get

# 4. Собрать APK
echo "🔨 Сборка APK..."
flutter build apk --release --android-skip-build-dependency-validation

# 5. Результат
echo ""
echo "✅ ГОТОВО!"
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    ls -lh build/app/outputs/flutter-apk/app-release.apk
    echo "📍 Путь: $(pwd)/build/app/outputs/flutter-apk/app-release.apk"
else
    echo "⚠️ APK не найден"
    ls -la build/app/outputs/flutter-apk/ 2>/dev/null || echo "Папка не существует"
fi
