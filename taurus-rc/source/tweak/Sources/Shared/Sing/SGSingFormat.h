#pragma once

enum {
    SGSingSampleRate = 44100,                          // Spotify's decoded source, stereo float
    SGSingWindowFrames = 88200,                        // two seconds, one run of the model
    SGSingHopFrames = SGSingWindowFrames * 3 / 4,      // 66150: a window every 1.5 s, half a second overlapping
    SGSingReserveFrames = SGSingSampleRate * 120 / 1000,
    SGSingTimelineFrames = SGSingSampleRate * 8,       // eight seconds of original kept for the worker
};
