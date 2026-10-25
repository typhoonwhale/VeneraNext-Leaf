import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ANDROID_NS = "http://schemas.android.com/apk/res/android"


class LeafAndroidIdentityTests(unittest.TestCase):
    def test_application_id_and_display_name_are_leaf_specific(self):
        gradle = (ROOT / "android/app/build.gradle").read_text()
        match = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "com.github.typhoonwhale.veneranext.leaf")
        self.assertIn('applicationIdSuffix ".debug"', gradle)

        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
        application = manifest.getroot().find("application")
        self.assertIsNotNone(application)
        self.assertEqual(
            application.attrib[f"{{{ANDROID_NS}}}label"], "@string/app_name"
        )
        strings = ET.parse(ROOT / "android/app/src/main/res/values/strings.xml")
        app_name = strings.getroot().find("string[@name='app_name']")
        self.assertIsNotNone(app_name)
        self.assertEqual(app_name.text, "Leaf")

    def test_provider_authority_uses_the_installed_application_id(self):
        plugin_manifest = ET.parse(
            ROOT / "packages/share_plus/android/src/main/AndroidManifest.xml"
        )
        providers = plugin_manifest.getroot().findall("./application/provider")
        self.assertEqual(len(providers), 1)
        authority = providers[0].attrib[f"{{{ANDROID_NS}}}authorities"]
        self.assertEqual(authority, "${applicationId}.flutter.share_provider")
        self.assertEqual(
            authority.replace("${applicationId}", "com.github.typhoonwhale.veneranext.leaf"),
            "com.github.typhoonwhale.veneranext.leaf.flutter.share_provider",
        )

    def test_leaf_does_not_register_upstream_web_links(self):
        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
        activity = manifest.getroot().find("./application/activity")
        self.assertIsNotNone(activity)
        actions = [
            action.attrib[f"{{{ANDROID_NS}}}name"]
            for intent_filter in activity.findall("intent-filter")
            for action in intent_filter.findall("action")
        ]
        self.assertIn("android.intent.action.MAIN", actions)
        self.assertIn("android.intent.action.SEND", actions)
        self.assertNotIn("android.intent.action.VIEW", actions)

    def test_release_requires_fixed_signing_material_in_gradle_and_ci(self):
        gradle = (ROOT / "android/app/build.gradle").read_text()
        self.assertIn('if (keystorePropertiesFile.exists())', gradle)
        self.assertIn('task.name == "preReleaseBuild"', gradle)
        self.assertIn("if (!releaseSigningAvailable)", gradle)
        self.assertIn("fixed signing key", gradle)

        pr_workflow = (ROOT / ".github/workflows/pr_build.yml").read_text()
        self.assertNotIn("keytool -genkeypair", pr_workflow)

        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        guard = workflow.index('if [[ -z "${STORE_FILE:-}"')
        decode = workflow.index('base64 --decode > android/keystore.jks')
        self.assertLess(guard, decode)
        self.assertIn("ANDROID_KEYSTORE and ANDROID_KEY_PROPERTIES", workflow)


if __name__ == "__main__":
    unittest.main()
