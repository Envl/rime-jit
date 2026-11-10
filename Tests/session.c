#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "rime_api.h"

static int candidate_index(RimeApi *api, RimeSessionId session, const char *keys,
                           const char *expected, const char *label) {
    api->clear_composition(session);
    for (const char *key = keys; *key; ++key) api->process_key(session, *key, 0);
    RIME_STRUCT(RimeContext, ctx);
    if (!api->get_context(session, &ctx)) return -1;
    int found = -1;
    for (int i = 0; i < ctx.menu.num_candidates; i++) {
        RimeCandidate candidate = ctx.menu.candidates[i];
        if (!strcmp(candidate.text, expected) && candidate.comment && strstr(candidate.comment, label)) {
            found = i;
            break;
        }
    }
    api->free_context(&ctx);
    return found;
}

static int commit_match(RimeApi *api, RimeSessionId session, const char *keys,
                        const char *expected, const char *label) {
    int found = candidate_index(api, session, keys, expected, label);
    if (found < 0 || !api->select_candidate_on_current_page(session, found)) return 0;
    RIME_STRUCT(RimeCommit, commit);
    if (!api->get_commit(session, &commit)) return 0;
    int ok = !strcmp(expected, commit.text);
    printf("%s -> %s (candidate %d)\n", keys, commit.text, found + 1);
    api->free_commit(&commit);
    return ok;
}

int main(int argc, char **argv) {
    if (argc != 5) return 2;
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
    if (strcmp(argv[4], "seed") == 0) {
        ok = ok && commit_match(api, session, "isqkybhh", "重庆银行", "屏");
        ok = ok && commit_match(api, session, "screencap", "ScreenCaptureKit", "屏");
        ok = ok && commit_match(api, session, "samplecrea", "sample-creator-toolkit", "屏");
        ok = ok && commit_match(api, session, "shellclick", "Shell Click", "屏");
        ok = ok && commit_match(api, session, "webse", "Web search", "屏");
        ok = ok && candidate_index(api, session, "datayetsjijpkz", "Data 页统计接口", "屏") == 0;
        ok = ok && candidate_index(api, session, "yetsjijpkz", "页统计接口", "屏") == 0;
        ok = ok && commit_match(api, session, "yetsjijpkz", "Data 页统计接口", "屏");
        ok = ok && commit_match(api, session, "isqkybhh", "重　庆  银行", "屏");
        ok = ok && commit_match(api, session, "localtools", "Local\u00a0 Tools", "屏");
        int visible = candidate_index(api, session, "rank", "Rank Visible", "屏");
        int recent = candidate_index(api, session, "rank", "Rank Recent", "屏");
        ok = ok && visible >= 0 && recent > visible;
        ok = ok && candidate_index(api, session, "rank", "Rank Old", "屏") < 0;
        ok = ok && candidate_index(api, session, "rankold", "Rank Old", "屏") >= 0;
        ok = ok && candidate_index(api, session, "rankexpired", "Rank Expired", "屏") < 0;
        ok = ok && unlink(argv[3]) == 0;
    }
    // Run once in the original process and once after a real librime restart.
    ok = ok && commit_match(api, session, "isqkybhh", "重　庆  银行", "记");
    ok = ok && commit_match(api, session, "datayetsjijpkz", "Data 页统计接口", "记");
    ok = ok && commit_match(api, session, "screencapturekit", "ScreenCaptureKit", "记");
    ok = ok && commit_match(api, session, "samplecre", "sample-creator-toolkit", "记");
    ok = ok && candidate_index(api, session, "rankold", "Rank Old", "记") < 0;
    api->destroy_session(session);
    api->finalize();
    if (!ok) fprintf(stderr, "Expected screen candidate missing from first page or failed to commit\n");
    return !ok;
}
