// Music Haptics' analyzer (Shared/Haptics/SGMusicAnalyzer.m, as the tweak compiles it) over a song on the
// Mac: the song is decoded at the rate asked for (the output's, 48 kHz on an iPhone), mixed to mono the way
// MusicHaptics.x mixes the output's buffers, handed over in IO buffers of the size asked for, and every event
// is written out one a line: K (a kick's tap), S (a snare's), L (the rumble's level), then the time in seconds,
// the intensity and the sharpness. score.py reads it against a song's onsets; `summary` prints what each
// Follows choice would play.
//
//     ./build.sh && build/haptics <song> <events.csv> [rate] [frames]
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Shared/Haptics/SGMusicAnalyzer.h"

typedef struct {
    FILE *out;
    unsigned kicks, snares, levels, rumbling;
    double lastTime;
} Run;

static void emit(const SGMusicEvent *event, void *context) {
    Run *run = context;
    char kind = event->kind == SGMusicEventKick ? 'K' : event->kind == SGMusicEventSnare ? 'S' : 'L';
    fprintf(run->out, "%c,%.5f,%.4f,%.4f\n", kind, event->hostTime / 1e9, event->intensity, event->sharpness);
    if (kind == 'K') run->kicks++;
    else if (kind == 'S') run->snares++;
    else {
        run->levels++;
        run->rumbling += event->intensity >= 0.05f;   // MusicHaptics.x's kRumbleStart
    }
    run->lastTime = event->hostTime / 1e9;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s <song> <events.csv> [rate] [frames]\n", argv[0]);
            return 2;
        }
        double rate = argc > 3 ? atof(argv[3]) : 44100;
        UInt32 frames = argc > 4 ? (UInt32)atoi(argv[4]) : 1024;
        ExtAudioFileRef file;
        if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[1])], &file)) {
            fprintf(stderr, "cannot open %s\n", argv[1]);
            return 1;
        }
        AudioStreamBasicDescription format = {rate, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
        ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
        Run run = {fopen(argv[2], "w")};
        SGMusicAnalyzer analyzer;
        SGMusicAnalyzerReset(&analyzer, rate, 1e9);
        float *stereo = malloc(frames * 2 * sizeof(float)), *mono = malloc(frames * sizeof(float));
        uint64_t done = 0;
        for (;;) {
            AudioBufferList list = {1, {{2, frames * 2 * (UInt32)sizeof(float), stereo}}};
            UInt32 count = frames;
            if (ExtAudioFileRead(file, &count, &list) || !count) break;
            for (UInt32 i = 0; i < count; i++) mono[i] = 0.5f * (stereo[2 * i] + stereo[2 * i + 1]);
            SGMusicAnalyzerProcess(&analyzer, mono, count, (uint64_t)(done / rate * 1e9), emit, &run);
            done += count;
        }
        fclose(run.out);
        ExtAudioFileDispose(file);
        double seconds = done / rate;
        printf("%.1f s at %.0f Hz in buffers of %u: kicks %u, snares %u (%.2f taps a second); Everything and Beat tap %.2f a second, "
               "Bass %.2f; the rumble is on for %.0f%% of the levels (Everything, Bass)\n",
               seconds, rate, (unsigned)frames, run.kicks, run.snares, (run.kicks + run.snares) / seconds, (run.kicks + run.snares) / seconds,
               run.kicks / seconds, run.levels ? 100.0 * run.rumbling / run.levels : 0);
    }
    return 0;
}
