package de.khonager.typesync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class TypeSyncUpcomingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateWidgets(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    private fun updateWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
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
            val imagePath = resolveImagePath(
                widgetData = widgetData,
                options = appWidgetManager.getAppWidgetOptions(widgetId),
            )
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

    private fun resolveImagePath(
        widgetData: SharedPreferences,
        options: Bundle?,
    ): String? {
        val widthDp = options?.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
            DEFAULT_WIDGET_WIDTH_DP,
        ) ?: DEFAULT_WIDGET_WIDTH_DP
        val heightDp = options?.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
            DEFAULT_WIDGET_HEIGHT_DP,
        ) ?: DEFAULT_WIDGET_HEIGHT_DP

        return IMAGE_VARIANTS
            .sortedBy { variant -> variant.distanceTo(widthDp, heightDp) }
            .asSequence()
            .mapNotNull { variant -> widgetData.getString(variant.key, null) }
            .firstOrNull()
    }

    companion object {
        private const val WIDGET_IMAGE_KEY = "typesync_upcoming_image"
        private const val COMPACT_WIDGET_IMAGE_KEY = "typesync_upcoming_image_280x140"
        private const val MEDIUM_TALL_WIDGET_IMAGE_KEY =
            "typesync_upcoming_image_360x232"
        private const val WIDE_WIDGET_IMAGE_KEY = "typesync_upcoming_image_480x176"
        private const val WIDE_TALL_WIDGET_IMAGE_KEY =
            "typesync_upcoming_image_480x232"
        private const val PLACEHOLDER_TITLE_KEY = "typesync_upcoming_placeholder_title"
        private const val PLACEHOLDER_SUBTITLE_KEY =
            "typesync_upcoming_placeholder_subtitle"
        private const val DEFAULT_WIDGET_WIDTH_DP = 360
        private const val DEFAULT_WIDGET_HEIGHT_DP = 176
        private val IMAGE_VARIANTS = listOf(
            WidgetImageVariant(COMPACT_WIDGET_IMAGE_KEY, 280, 140),
            WidgetImageVariant(WIDGET_IMAGE_KEY, 360, 176),
            WidgetImageVariant(MEDIUM_TALL_WIDGET_IMAGE_KEY, 360, 232),
            WidgetImageVariant(WIDE_WIDGET_IMAGE_KEY, 480, 176),
            WidgetImageVariant(WIDE_TALL_WIDGET_IMAGE_KEY, 480, 232),
        )
    }
}

private data class WidgetImageVariant(
    val key: String,
    val widthDp: Int,
    val heightDp: Int,
) {
    fun distanceTo(targetWidthDp: Int, targetHeightDp: Int): Long {
        val widthDelta = (widthDp - targetWidthDp).toLong()
        val heightDelta = (heightDp - targetHeightDp).toLong()
        return (widthDelta * widthDelta) + (heightDelta * heightDelta)
    }
}
