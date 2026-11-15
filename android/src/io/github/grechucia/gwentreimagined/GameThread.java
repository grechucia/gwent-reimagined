// Runs game logic off the render thread while keeping it single-threaded, like the main actor in the Swift version.
package io.github.grechucia.gwentreimagined;

import android.util.Log;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.locks.ReentrantLock;

/**
 * All game state is guarded by one lock. The render thread holds it while drawing a frame; game tasks hold it while
 * they run and release it only while they wait (pauses for animations, waiting for the player's choice).
 */
final class GameThread {
    static final ReentrantLock LOCK = new ReentrantLock();
    private static final ExecutorService EXECUTOR = Executors.newCachedThreadPool();
    private GameThread() {}

    /** Starts a game task (the equivalent of `Task { @MainActor in ... }`). */
    static void launch(Runnable task) {
        EXECUTOR.execute(() -> {
            LOCK.lock();
            try { task.run(); }
            catch (Throwable t) { Log.e("Gwent", "Game task failed", t); }
            finally { LOCK.unlock(); }
        });
    }

    /** Waits without holding the lock, so the render thread can draw in the meantime. */
    static void sleep(double seconds) {
        int holds = releaseAll();
        try { Thread.sleep((long) (seconds * 1000)); } catch (InterruptedException ignored) {}
        reacquire(holds);
    }

    /** Releases every hold of the lock owned by the current thread and returns how many there were. */
    static int releaseAll() {
        int holds = LOCK.getHoldCount();
        for (int i = 0; i < holds; i++) LOCK.unlock();
        return holds;
    }
    /** Takes the lock again the given number of times. */
    static void reacquire(int holds) { for (int i = 0; i < holds; i++) LOCK.lock(); }
}
