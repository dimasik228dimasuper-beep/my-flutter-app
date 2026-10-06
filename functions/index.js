const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.onPushOutbox = functions.database
  .ref('/push_outbox/{id}')
  .onCreate(async (snap, context) => {
    const data = snap.val() || {};
    const toUid = data.to_uid;
    if (!toUid) {
      await snap.ref.remove();
      return null;
    }

    let token = null;
    const t1 = await admin.database().ref('fcm_tokens/' + toUid + '/token').once('value');
    if (t1.exists()) token = t1.val();
    if (!token) {
      const t2 = await admin.database()
        .ref('tables/push_subscriptions/' + toUid + '/token')
        .once('value');
      if (t2.exists()) token = t2.val();
    }
    if (!token) {
      await snap.ref.update({ sent: false, error: 'no_token' });
      return null;
    }

    const payload = {
      notification: {
        title: String(data.title || 'SLine').slice(0, 100),
        body: String(data.body || '').slice(0, 200),
      },
      data: {
        chat_key: String(data.chat_key || ''),
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: token,
      android: {
        priority: 'high',
        notification: { channelId: 'sline_messages', sound: 'default' },
      },
    };

    try {
      await admin.messaging().send(payload);
      await snap.ref.update({ sent: true, sent_at: Date.now() });
    } catch (e) {
      await snap.ref.update({ sent: false, error: String(e).slice(0, 200) });
    }
    return null;
  });