import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  @override
  Widget build(BuildContext context) {
    final eink = GlobalPreferenceStore(appdata.settings).appearance.einkTheme;
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        SwitchSetting.preference(
          title: "E-Ink mode".tl,
          subtitle:
              "Black-and-white high-contrast interface with reduced animations. Comic images are not altered."
                  .tl,
          preference: AppearancePreferences.eInkMode,
          onChanged: () => appNavigation.forceRebuild(),
        ).toSliver(),
        SelectSetting.preference(
          title: "Theme Mode".tl,
          enabled: !eink,
          subtitle: eink ? "Fixed to black and white in E-Ink mode".tl : null,
          preference: AppearancePreferences.themeMode,
          optionTranslation: {
            "system": "System".tl,
            "light": "Light".tl,
            "dark": "Dark".tl,
          },
          onChanged: () async {
            appNavigation.forceRebuild();
          },
        ).toSliver(),
        SelectSetting.preference(
          title: "Theme Color".tl,
          enabled: !eink,
          subtitle: eink ? "Fixed to black and white in E-Ink mode".tl : null,
          preference: AppearancePreferences.color,
          optionTranslation: {
            "system": "System".tl,
            "red": "Red".tl,
            "pink": "Pink".tl,
            "purple": "Purple".tl,
            "green": "Green".tl,
            "orange": "Orange".tl,
            "blue": "Blue".tl,
          },
          onChanged: () async {
            await App.init();
            appNavigation.forceRebuild();
          },
        ).toSliver(),
      ],
    );
  }
}
