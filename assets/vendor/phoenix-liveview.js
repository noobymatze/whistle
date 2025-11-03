const plugin = require("tailwindcss/plugin");

module.exports = plugin(function({ addVariant }) {
  // Allows prefixing tailwind classes with LiveView classes to add rules
  // only when LiveView classes are applied, for example:
  //
  //     <div class="phx-click-loading:animate-ping">
  //
  addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"]);
  addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"]);
  addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"]);
  addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"]);
});
