// Platform services the activity provides to the shared game UI: settings, dialogs, links and the folder picker.
package io.github.grechucia.gwentreimagined;

import java.util.List;
import java.util.function.Consumer;

/** Settings and system services shown in Options and used by the screens. */
interface GameHost {
    /** Render resolution height (0 = native). */
    int renderRes();
    void setRenderRes(int height);
    /** Frame limits that divide the display refresh rate. */
    List<Integer> availableFrameLimits();
    int effectiveFrameLimit();
    void setFrameLimit(int limit);
    /** Fill the whole screen (true) or keep 16:9 with black bars (false). */
    boolean fillScreen();
    void setFillScreen(boolean on);
    /** Small screens get larger card descriptions. */
    boolean isPhone();
    /** Opens a URL in the browser. */
    void openURL(String url);
    /** Asks for a line of text; `done` receives null when cancelled (called with the game lock held). */
    void askText(String title, String message, String placeholder, String current, Consumer<String> done);
    /** Lets the user choose a folder for the save file; `done` receives true when one was chosen (called with the game lock held). */
    void pickFolder(Consumer<Boolean> done);
    /** Integer setting stored on the device. */
    int intSetting(String key, int fallback);
    void setIntSetting(String key, int value);
    /** Saves the chosen language. */
    void setLanguage(String code);
}
