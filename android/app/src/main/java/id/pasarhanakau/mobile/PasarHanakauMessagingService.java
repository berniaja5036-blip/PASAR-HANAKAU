package id.pasarhanakau.mobile;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class PasarHanakauMessagingService extends FirebaseMessagingService {
    public static final String CHANNEL_ID = "pasar_hanakau_updates";
    private static final String PREFS = "pasar_hanakau_notifications";

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public void onNewToken(String token) {
        super.onNewToken(token);
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putString("fcm_token", token)
            .putLong("token_updated_at", System.currentTimeMillis())
            .apply();
    }

    @Override
    public void onMessageReceived(RemoteMessage message) {
        super.onMessageReceived(message);
        String title = message.getNotification() != null
            ? message.getNotification().getTitle() : message.getData().get("title");
        String body = message.getNotification() != null
            ? message.getNotification().getBody() : message.getData().get("body");
        if (title == null || title.trim().isEmpty()) title = "Pasar Hanakau";
        if (body == null || body.trim().isEmpty()) body = "Ada pemberitahuan baru untuk Anda.";
        showNotification(title, body, message.getData().get("route"));
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "Pemberitahuan Pasar Hanakau",
                NotificationManager.IMPORTANCE_DEFAULT);
            channel.setDescription("Informasi pesanan, toko, pengiriman, dan aktivitas akun.");
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) manager.createNotificationChannel(channel);
        }
    }

    private void showNotification(String title, String body, String route) {
        createNotificationChannel();
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        if (route != null && !route.isEmpty()) intent.putExtra("notification_route", route);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, (int) (System.currentTimeMillis() & 0x0fffffff), intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(getApplicationInfo().icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent);
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            NotificationManagerCompat.from(this).notify(
                (int) (System.currentTimeMillis() & 0x0fffffff), builder.build());
        }
    }
}
