"use strict";

class StoreContextShim {
  static getDefault() {
    return new StoreContextShim();
  }

  getAppAndOptionalStorePackageUpdatesAsync(callback) {
    const result = { size: 0 };
    if (typeof callback === "function") {
      process.nextTick(() => callback(null, result));
    }
    return Promise.resolve(result);
  }
}

module.exports = {
  StoreContext: StoreContextShim
};
