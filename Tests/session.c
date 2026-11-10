#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "rime_api.h"

static int commit_match(RimeApi *api, RimeSessionId session, const char *keys, const char *expected) {
    api->clear_composition(session);
    for (const char *key = keys; *key; ++key) api->process_key(session, *key, 0);
    RIME_STRUCT(RimeContext, ctx);
    if (!api->get_context(session, &ctx)) return 0;
    int found = -1;
    for (int i = 0; i < ctx.menu.num_candidates; i++) {
        RimeCandidate candidate = ctx.menu.candidates[i];
        if (!strcmp(candidate.text, expected) && candidate.comment && strstr(candidate.comment, "屏")) {
            found = i;
            break;
        }
    }
    api->free_context(&ctx);
    if (found < 0 || !api->select_candidate_on_current_page(session, found)) return 0;
    RIME_STRUCT(RimeCommit, commit);
    if (!api->get_commit(session, &commit)) return 0;
    int ok = !strcmp(expected, commit.text);
    printf("%s -> %s (candidate %d)\n", keys, commit.text, found + 1);
    api->free_commit(&commit);
    return ok;
}

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    RimeApi *api = rime_get_api();
    const char *modules[] = {"default", "lua", NULL};
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = argv[1];
    traits.user_data_dir = argv[2];
    traits.app_name = "rime.screenwords-test";
    traits.min_log_level = 2;
    traits.log_dir = "";
    traits.modules = modules;
    api->setup(&traits);
    api->initialize(&traits);
    RimeSessionId session = api->create_session();
    int ok = api->select_schema(session, "double_pinyin_flypy");
    api->set_option(session, "ascii_mode", False);
    api->set_option(session, "simplification", True);
    ok = ok && commit_match(api, session, "isqkybhh", "重庆银行");
    ok = ok && commit_match(api, session, "screencap", "ScreenCaptureKit");
    ok = ok && commit_match(api, session, "samplecrea", "sample-creator-toolkit");
    ok = ok && commit_match(api, session, "shellclick", "Shell Click");
    ok = ok && commit_match(api, session, "webse", "Web search");
    if (ok && unlink(argv[3]) == 0) {
        // Query the same Lua environment again after the producer pauses.
        ok = !commit_match(api, session, "screencap", "ScreenCaptureKit");
        if (ok) puts("Pausing removes screen candidates in the same session");
    } else {
        ok = 0;
    }
    api->destroy_session(session);
    api->finalize();
    if (!ok) fprintf(stderr, "Expected screen candidate missing from first page or failed to commit\n");
    return !ok;
}
