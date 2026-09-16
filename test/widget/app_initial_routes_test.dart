import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/app/app.dart';
import 'package:typesync/core/routes/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('editor browser path does not create a ghost editor route', () {
    final routes = generateTypeSyncInitialRoutes(AppRouter.editor);

    expect(routes, hasLength(1));
    expect(routes.single.settings.name, AppRouter.home);
  });

  test('split editor browser path also starts from one home route', () {
    final routes = generateTypeSyncInitialRoutes(AppRouter.splitEditor);

    expect(routes, hasLength(1));
    expect(routes.single.settings.name, AppRouter.home);
  });

  test('email sign-in links retain their external entry route', () {
    final routes = generateTypeSyncInitialRoutes(
      '${AppRouter.finishSignUp}?email=user%40example.com',
    );

    expect(routes, hasLength(1));
    expect(routes.single.settings.name, AppRouter.finishSignUp);
  });
}
