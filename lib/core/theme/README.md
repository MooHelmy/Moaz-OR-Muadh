# نظام الثيم (Theme System) 🎨

## مميزات النظام:

✅ **تبديل سلس بين Dark Mode و Light Mode**
✅ **ألوان احترافية ومتناسقة**
✅ **حفظ تلقائي للإعدادات في SharedPreferences**
✅ **دعم كامل لـ Material 3**
✅ **Typography احترافي لـ Arabic و English**
✅ **Colors معرفة بوضوح وسهولة الوصول إليها**

---

## الملفات الرئيسية:

### 1. **app_colors.dart**
- يحتوي على جميع الألوان المستخدمة في التطبيق
- تقسيم واضح لـ Light و Dark ألوان
- ألوان الحالة (Success, Warning, Error)

### 2. **light_theme.dart** و **dark_theme.dart**
- تعريف كامل الـ ThemeData للوضع الفاتح والمظلم
- تنسيق الـ AppBar, Buttons, Input Fields, Cards, إلخ

### 3. **app_theme.dart**
- ملف مركزي يجمع light و dark theme

### 4. **theme_provider.dart**
- Riverpod provider لإدارة حالة الثيم
- تبديل الثيم مع حفظ تلقائي

### 5. **theme_toggle_button.dart**
- Widget جاهز لتبديل الثيم
- يمكن إضافته في أي مكان في التطبيق

### 6. **theme_extensions.dart**
- Extensions مفيدة للوصول للألوان بسهولة

---

## الاستخدام:

### الحصول على الألوان:
```dart
// الطريقة 1: Theme.of(context)
Color primary = Theme.of(context).primaryColor;

// الطريقة 2: Extension (أسهل)
Color primary = context.primaryColor;
Color secondary = context.secondaryColor;
Color bg = context.backgroundColor;
```

### الحصول على Text Styles:
```dart
TextStyle title = context.titleLarge;
TextStyle body = context.bodyMedium;
```

### تبديل الثيم:
```dart
ref.read(themeNotifierProvider.notifier).toggleTheme();

// أو تعيين وضع معين:
await ref.read(themeNotifierProvider.notifier).setDarkMode(true);
```

### التحقق من الوضع الحالي:
```dart
bool isDark = context.isDarkMode;
bool isLight = context.isLightMode;
```

### إضافة زر تبديل الثيم:
```dart
import 'package:medi_guard/core/theme/theme_toggle_button.dart';

ThemeToggleButton()
```

---

## مثال عملي:

```dart
class MyWidget extends ConsumerWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: context.primaryColor,
      child: Text(
        'مرحباً',
        style: context.titleLarge.copyWith(
          color: context.textPrimary,
        ),
      ),
    );
  }
}
```

---

## الألوان المتاحة:

### Primary Colors:
- `AppColors.primaryLight` (#064E3B) - الأخضر الداكن
- `AppColors.primaryDark` (#10B981) - الأخضر الفاتح

### Status Colors:
- `AppColors.success` (#10B981) - نجاح
- `AppColors.warning` (#F59E0B) - تحذير
- `AppColors.error` (#EF4444) - خطأ
- `AppColors.info` (#3B82F6) - معلومة

---

## ملاحظات:

- الثيم محفوظ تلقائياً ويتم تحميله عند بدء التطبيق
- جميع الـ Widgets تستخدم الثيم تلقائياً
- يمكن تخصيص الثيم أكثر في `light_theme.dart` و `dark_theme.dart`
- الـ Extensions توفر وصول سريع للألوان والـ text styles
