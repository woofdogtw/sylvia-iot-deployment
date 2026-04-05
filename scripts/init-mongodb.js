// MongoDB seed data for Sylvia-IoT
// Run with: mongosh < init-mongodb.js
// Idempotent - safe to run multiple times

use('sylvia-iot-auth');

db.user.updateOne(
    { userId: 'admin' },
    {
        $setOnInsert: {
            userId: 'admin',
            account: 'admin',
            createdAt: new Date(0),
            modifiedAt: new Date(0),
            verifiedAt: new Date(0),
            expiredAt: null,
            disabledAt: null,
            roles: { admin: true, dev: false },
            password: '27258772d876ffcef7ca2c75d6f4e6bcd81c203bd3e93c0791c736e5a2df4afa',
            salt: 'YsBsou2O',
            name: 'Admin',
            info: {}
        }
    },
    { upsert: true }
);
print('user: admin');

db.client.updateOne(
    { clientId: 'public' },
    {
        $setOnInsert: {
            clientId: 'public',
            createdAt: new Date(0),
            modifiedAt: new Date(0),
            clientSecret: null,
            redirectUris: [
                'http://localhost:1080/auth/oauth2/redirect',
                'http://localhost:1080/#/auth/callback'
            ],
            scopes: [],
            userId: 'admin',
            name: 'Public',
            imageUrl: null
        }
    },
    { upsert: true }
);
print('client: public');

db.client.updateOne(
    { clientId: 'private' },
    {
        $setOnInsert: {
            clientId: 'private',
            createdAt: new Date(0),
            modifiedAt: new Date(0),
            clientSecret: 'secret',
            redirectUris: ['http://localhost:1080/auth/oauth2/redirect'],
            scopes: [],
            userId: 'admin',
            name: 'Private',
            imageUrl: null
        }
    },
    { upsert: true }
);
print('client: private');

db.client.updateOne(
    { clientId: 'sylvia-iot-gui' },
    {
        $setOnInsert: {
            clientId: 'sylvia-iot-gui',
            createdAt: new Date(0),
            modifiedAt: new Date(0),
            clientSecret: null,
            redirectUris: ['http://localhost:1080/#/auth/callback'],
            scopes: [],
            userId: 'admin',
            name: 'Sylvia-IoT GUI',
            imageUrl: null
        }
    },
    { upsert: true }
);
print('client: sylvia-iot-gui');

print('MongoDB seed data initialized.');
