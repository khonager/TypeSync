package de.khonager.typesync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class TypeSyncUpcomingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        val imagePath = widgetData.getString(WIDGET_IMAGE_KEY, null)
        val placeholderTitle = widgetData.getString(
            PLACEHOLDER_TITLE_KEY,
            "Upcoming in TypeSync",
        )
        val placeholderSubtitle = widgetData.getString(
            PLACEHOLDER_SUBTITLE_KEY,
            "Open the app to refresh this widget",
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.typesync_upcoming_widget)
            val bitmap = imagePath
                ?.let(::File)
                ?.takeIf(File::exists)
                ?.let { BitmapFactory.decodeFile(it.absolutePath) }

            if (bitmap != null) {
                views.setViewVisibility(R.id.typesync_widget_image, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.typesync_widget_placeholder, android.view.View.GONE)
                views.setImageViewBitmap(R.id.typesync_widget_image, bitmap)
            } else {
                views.setViewVisibility(R.id.typesync_widget_image, android.view.View.GONE)
                views.setViewVisibility(R.id.typesync_widget_placeholder, android.view.View.VISIBLE)
                views.setTextViewText(R.id.typesync_widget_placeholder_title, placeholderTitle)
                views.setTextViewText(
                    R.id.typesync_widget_placeholder_subtitle,
                    placeholderSubtitle,
                )
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            views.setOnClickPendingIntent(R.id.typesync_widget_root, pendingIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    companion object {
        private const val WIDGET_IMAGE_KEY = "typesync_upcoming_image"
        private const val PLACEHOLDER_TITLE_KEY = "typesync_upcoming_placeholder_title"
        private const val PLACEHOLDER_SUBTITLE_KEY =
            "typesync_upcoming_placeholder_subtitle"
    }
}
