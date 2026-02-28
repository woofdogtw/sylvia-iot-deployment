// Runtime configuration for Sylvia-IoT GUI
// Modify this file for different deployment environments.
// No rebuild is required after changes.
window.config = {
  auth: {
    baseUrl: '/auth',
    clientId: 'sylvia-iot-gui',
    redirectUri: 'http://localhost/#/auth/callback',
    scopes: [],
  },
  coremgr: {
    baseUrl: '/coremgr',
  },
  data: {
    baseUrl: '/data',
  },
  router: {
    baseUrl: '/router',
  },
  // External plugins: URLs to ES module JS files with a default plugin export.
  // Example: plugins: ['/js/plugins/my-plugin.js', 'https://cdn.example.com/plugin.js']
  // plugins: [],
}
