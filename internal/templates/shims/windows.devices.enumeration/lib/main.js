"use strict";

class EmptyDeviceCollection {
  constructor() {
    this.size = 0;
  }

  getAt() {
    throw new Error("No devices");
  }
}

class DeviceInformationShim {
  static findAllAsync(_kind, callback) {
    const result = new EmptyDeviceCollection();
    if (typeof callback === "function") {
      process.nextTick(() => callback(null, result));
    }
    return Promise.resolve(result);
  }
}

module.exports = {
  DeviceInformation: DeviceInformationShim
};
