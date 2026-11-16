import { window } from '@kit.ArkUI';
import { describe, expect, it } from '@ohos/hypium';
import {
  ViewSettingsTools, ViewSettingsWindow
} from '../main/ets/capabilities/view/ViewSettingsTools';
import { getTestUiAbilityContext } from './TestContext';

class RecordingViewSettingsWindow implements ViewSettingsWindow {
  readonly applied: window.SystemBarProperties[] = [];

  getWindowSystemBarProperties(): window.SystemBarProperties {
    return {
      statusBarColor: '#010203',
      statusBarContentColor: '#040506',
      navigationBarColor: '#070809',
      navigationBarContentColor: '#0A0B0C'
    };
  }

  setWindowSystemBarProperties(properties: window.SystemBarProperties): Promise<void> {
    this.applied.push(properties);
    return Promise.resolve();
  }
}

export default function viewSettingsToolsTest(): void {
  describe('ViewSettingsTools', () => {
    it('mapsVkSettingsToHarmonySystemBars', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      const tools: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));

      await tools.apply({
        statusBarStyle: 'light',
        actionBarColor: '#112233',
        navigationBarColor: '#445566'
      });

      expect(appWindow.applied.length).assertEqual(1);
      expect(appWindow.applied[0].statusBarContentColor).assertEqual('#FFFFFF');
      expect(appWindow.applied[0].isStatusBarLightIcon).assertTrue();
      expect(appWindow.applied[0].statusBarColor).assertEqual('#112233');
      expect(appWindow.applied[0].navigationBarColor).assertEqual('#445566');
    });

    it('restoresOriginalSystemBarsOnDispose', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      const tools: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));

      await tools.apply({
        statusBarStyle: 'dark',
        actionBarColor: '#112233',
        navigationBarColor: '#445566'
      });
      tools.dispose();
      await Promise.resolve();

      expect(appWindow.applied.length).assertEqual(2);
      expect(appWindow.applied[1].statusBarColor).assertEqual('#010203');
      expect(appWindow.applied[1].statusBarContentColor).assertEqual('#040506');
      expect(appWindow.applied[1].navigationBarColor).assertEqual('#070809');
      expect(appWindow.applied[1].navigationBarContentColor).assertEqual('#0A0B0C');
    });

    it('mapsVkNoneActionBarColorToTransparentStatusBar', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      const tools: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));

      await tools.apply({
        statusBarStyle: 'light',
        actionBarColor: 'none'
      });

      expect(appWindow.applied[0].statusBarColor).assertEqual('#00000000');
    });

    it('doesNotApplyAfterPageCleanupWhileWindowIsLoading', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      let resolveWindow: ((value: ViewSettingsWindow) => void) | undefined;
      const pendingWindow: Promise<ViewSettingsWindow> =
        new Promise<ViewSettingsWindow>((resolve: (value: ViewSettingsWindow) => void): void => {
          resolveWindow = resolve;
        });
      const tools: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => pendingWindow);

      const applying: Promise<void> = tools.apply({ statusBarStyle: 'light' });
      tools.dispose();
      if (resolveWindow) {
        resolveWindow(appWindow);
      }
      await applying;

      expect(appWindow.applied.length).assertEqual(0);
    });

    it('keepsLatestSessionStyleUntilLastSharedWindowOwnerDisposes', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      const first: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));
      const second: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));

      await first.apply({ statusBarStyle: 'light', actionBarColor: '#111111' });
      await second.apply({ statusBarStyle: 'dark', actionBarColor: '#222222' });
      first.dispose();

      expect(appWindow.applied.length).assertEqual(2);
      expect(appWindow.applied[1].statusBarColor).assertEqual('#222222');

      second.dispose();
      await Promise.resolve();

      expect(appWindow.applied.length).assertEqual(3);
      expect(appWindow.applied[2].statusBarColor).assertEqual('#010203');
    });

    it('restoresPreviousOwnerCompleteStateWhenOptionalColorsWereOmitted', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      const first: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));
      const second: ViewSettingsTools = new ViewSettingsTools(
        getTestUiAbilityContext(), (): Promise<ViewSettingsWindow> => Promise.resolve(appWindow));

      await first.apply({ statusBarStyle: 'light' });
      await second.apply({ statusBarStyle: 'dark', actionBarColor: '#222222' });
      second.dispose();
      await Promise.resolve();

      expect(appWindow.applied.length).assertEqual(3);
      expect(appWindow.applied[2].statusBarColor).assertEqual('#010203');
      first.dispose();
    });

    it('keepsLatestCallWhenWindowPromisesResolveInReverseOrder', 0, async () => {
      const appWindow: RecordingViewSettingsWindow = new RecordingViewSettingsWindow();
      let resolveFirst: ((value: ViewSettingsWindow) => void) | undefined;
      let resolveSecond: ((value: ViewSettingsWindow) => void) | undefined;
      const firstWindow: Promise<ViewSettingsWindow> =
        new Promise<ViewSettingsWindow>((resolve: (value: ViewSettingsWindow) => void): void => {
          resolveFirst = resolve;
        });
      const secondWindow: Promise<ViewSettingsWindow> =
        new Promise<ViewSettingsWindow>((resolve: (value: ViewSettingsWindow) => void): void => {
          resolveSecond = resolve;
        });
      let callCount: number = 0;
      const tools: ViewSettingsTools = new ViewSettingsTools(getTestUiAbilityContext(),
        (): Promise<ViewSettingsWindow> => {
          callCount++;
          return callCount === 1 ? firstWindow : secondWindow;
        });

      const firstApplying: Promise<void> =
        tools.apply({ statusBarStyle: 'light', actionBarColor: '#111111' });
      const secondApplying: Promise<void> =
        tools.apply({ statusBarStyle: 'dark', actionBarColor: '#222222' });
      if (resolveSecond) {
        resolveSecond(appWindow);
      }
      await secondApplying;
      if (resolveFirst) {
        resolveFirst(appWindow);
      }
      await firstApplying;

      expect(appWindow.applied.length).assertEqual(1);
      expect(appWindow.applied[0].statusBarColor).assertEqual('#222222');
      tools.dispose();
    });
  });
}
