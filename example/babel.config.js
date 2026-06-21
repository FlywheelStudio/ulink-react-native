module.exports = function (api) {
  api.cache(true);
  return {
    // Use require.resolve so babel picks up the example's own babel-preset-expo
    // (under expo/node_modules/), not the parent SDK's top-level one which
    // lacks react-refresh and causes a "Cannot find module 'react-refresh/babel'" error.
    presets: [require.resolve('expo/node_modules/babel-preset-expo')],
  };
};
