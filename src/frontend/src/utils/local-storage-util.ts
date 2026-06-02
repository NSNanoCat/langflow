/**
 * Safely reads a string value from localStorage.
 *
 * @param key - Storage key to read.
 * @returns The stored value, or null when storage is unavailable.
 */
export const getLocalStorage = (key: string): string | null => {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
};

/**
 * Safely writes a string value to localStorage.
 *
 * @param key - Storage key to write.
 * @param value - Storage value to write.
 * @returns Nothing.
 */
export const setLocalStorage = (key: string, value: string): void => {
  try {
    localStorage.setItem(key, value);
  } catch {}
};

/**
 * Safely removes a value from localStorage.
 *
 * @param key - Storage key to remove.
 * @returns Nothing.
 */
export const removeLocalStorage = (key: string): void => {
  try {
    localStorage.removeItem(key);
  } catch {}
};
