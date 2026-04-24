package com.example.music_player

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class MusicWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.music_widget).apply {
                // Set text data
                setTextViewText(R.id.widget_song_title, widgetData.getString("song_title", "No song playing"))
                setTextViewText(R.id.widget_song_artist, widgetData.getString("song_artist", ""))

                // Set play/pause icon based on state
                val isPlaying = widgetData.getBoolean("is_playing", false)
                setImageViewResource(
                    R.id.widget_btn_play_pause,
                    if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
                )

                // Setup PendingIntents for background actions
                val playPauseIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("home_widget://playpause")
                )
                setOnClickPendingIntent(R.id.widget_btn_play_pause, playPauseIntent)

                val skipNextIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("home_widget://skipnext")
                )
                setOnClickPendingIntent(R.id.widget_btn_next, skipNextIntent)

                val skipPrevIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("home_widget://skipprevious")
                )
                setOnClickPendingIntent(R.id.widget_btn_prev, skipPrevIntent)
                
                // Allow tapping the text area to open the app (optional)
                // val launchIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                // setOnClickPendingIntent(R.id.widget_song_title, launchIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
