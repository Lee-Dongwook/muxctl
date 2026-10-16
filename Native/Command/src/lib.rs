use std::cell::RefCell;
use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::slice;
use std::str;

use nucleo::pattern::{Atom, AtomKind, CaseMatching, Normalization, Pattern};
use nucleo::{Config, Matcher, Utf32Str};

#[repr(C)]
pub struct NucleoCandidateSpan {
    title_offset: usize,
    title_len: usize,
    search_offset: usize,
    search_len: usize,
    rank: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NucleoMatch {
    index: usize,
    score: f64,
    rank: i32,
}

struct Candidate {
    title: String,
    search_title: String,
    search_text: String,
    search_lines: Vec<String>,
    rank: i32,
    ascii_prefilter_safe: bool,
    ascii_mask_low: u64,
    ascii_mask_high: u64,
    title_initials: Vec<char>,
    title_char_count: usize,
}

struct ScoredCandidate {
    index: usize,
    score: f64,
    rank: i32,
}

struct InitialismQuery {
    chars: Vec<char>,
}

struct SearchToken {
    text: String,
    pattern: Pattern,
    initialism_query: Option<InitialismQuery>,
}

struct TitleLiteralQuery {
    exact: Atom,
    prefix: Atom,
    token_count: usize,
}

impl TitleLiteralQuery {
    fn new(query: &str) -> TitleLiteralQuery {
        TitleLiteralQuery {
            exact: Atom::new(
                query,
                CaseMatching::Ignore,
                Normalization::Smart,
                AtomKind::Exact,
                true,
            ),
            prefix: Atom::new(
                query,
                CaseMatching::Ignore,
                Normalization::Smart,
                AtomKind::Prefix,
                true,
            ),
            token_count: query.split_whitespace().count().max(1),
        }
    }
}

struct WorstFirstScoredCandidate(ScoredCandidate);

impl PartialEq for WorstFirstScoredCandidate {
    fn eq(&self, other: &Self) -> bool {
        scored_candidate_order(&self.0, &other.0) == Ordering::Equal
    }
}

impl Eq for WorstFirstScoredCandidate {}

impl PartialOrd for WorstFirstScoredCandidate {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for WorstFirstScoredCandidate {
    fn cmp(&self, other: &Self) -> Ordering {
        scored_candidate_order(&self.0, &other.0)
    }
}

struct SearchState {
    matcher: Matcher,
    utf32_buf: Vec<char>,
}

impl SearchState {
    fn score_text(&mut self, pattern: &Pattern, text: &str) -> Option<u32> {
        self.utf32_buf.clear();
        pattern.score(Utf32Str::new(text, &mut self.utf32_buf), &mut self.matcher)
    }

    fn atom_score(&mut self, atom: &Atom, text: &str) -> Option<u16> {
        self.utf32_buf.clear();
        atom.score(Utf32Str::new(text, &mut self.utf32_buf), &mut self.matcher)
    }
}

pub struct NucleoIndex {
    candidates: Vec<Candidate>,
}

thread_local! {
    static SEARCH_STATE: RefCell<SearchState> = RefCell::new(SearchState {
        matcher: Matcher::new(Config::DEFAULT),
        utf32_buf: Vec::new(),
    });
}

#[no_mangle]
pub extern "C" fn _nucleo_ffi_version() -> u32 {
    2
}

#[no_mangle]
pub unsafe extern "C" fn cmux_nucleo_index_create(
    blob_ptr: *const u8,
    blob_len: usize,
    spans_ptr: *const NucleoCandidateSpan,
    span_count: usize,
) -> *mut NucleoIndex {
    if blob_ptr.is_null() || spans_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let blob = slice::from_raw_parts(blob_ptr, blob_len);
    let spans = slice::from_raw_parts(spans_ptr, span_count);
    let mut candidates = Vec::with_capacity(span_count);

    for span in spans {
        let Some(title) = text_from_blob(blob, span.title_offset, span.title_len) else {
            return std::ptr::null_mut();
        };
        let Some(search_text) = text_from_blob(blob, span.search_offset, span.search_len) else {
            return std::ptr::null_mut();
        };
        let ascii_prefilter_safe = title.is_ascii() && search_text.is_ascii();
        let (title_low, title_high) = ascii_mask(title);
        let (search_low, search_high) = ascii_mask(search_text);
        let title_initials = title_word_initials(title);
        let title_char_count = title.chars().count();
        let search_title = title_search_word_text(title);
        let search_lines = search_text.lines().map(str::to_owned).collect();
        candidates.push(Candidate {
            title: title.to_owned(),
            search_title,
            search_text: search_text.to_owned(),
            search_lines,
            rank: span.rank,
            ascii_prefilter_safe,
            ascii_mask_low: title_low | search_low,
            ascii_mask_high: title_high | search_high,
            title_initials,
            title_char_count,
        });
    }

    Box::into_raw(Box::new(NucleoIndex { candidates }))
}

#[no_mangle]
pub unsafe extern "C" fn _nucleo_index_destroy(index: *mut NucleoIndex) {
    if !index.is_null() {
        drop(Box::from_raw(index));
    }
}

#[no_mangle]
pub unsafe extern "C" fn _nucleo_index_search(
    index: *mut NucleoIndex,
    query_ptr: *const u8,
    query_len: usize,
    result_limit: usize,
    out_matches: *mut NucleoMatch,
    out_capacity: usize,
    out_count: *mut usize,
) -> i32 {
    _nucleo_index_search_impl(
        index,
        query_ptr,
        query_len,
        result_limit,
        std::ptr::null(),
        0,
        out_matches,
        out_capacity,
        out_count,
    )
}


#[no_mangle]
pub unsafe extern "C" fn _nucleo_index_search_with_boosts(
    index: *mut NucleoIndex,
    query_ptr: *const u8,
    query_len: usize,
    result_limit: usize,
    boosts_ptr: *const i32,
    boosts_count: usize,
    out_matches: *mut NucleoMatch,
    out_capacity: usize,
    out_count: *mut usize,
) -> i32 {
    _nucleo_index_search_impl(
        index,
        query_ptr,
        query_len,
        result_limit,
        boosts_ptr,
        boosts_count,
        out_matches,
        out_capacity,
        out_count,
    )
}

unsafe fn _nucleo_index_search_impl(
    index: *mut NucleoIndex,
    query_ptr: *const u8,
    query_len: usize,
    result_limit: usize,
    boosts_ptr: *const i32,
    boosts_count: usize,
    out_matches: *mut NucleoMatch,
    out_capacity: usize,
    out_count: *mut usize,
) -> i32 {
    if index.is_null() || out_count.is_null() {
        return -1;
    }
    *out_count = 0;
    if result_limit == 0 || out_capacity == 0 {
        return 0;
    }
    if out_matches.is_null() || (query_ptr.is_null() && query_len > 0) {
        return -1;
    }

    let index = &*index;
    let query_bytes = if query_len == 0 {
        &[]
    } else {
        slice::from_raw_parts(query_ptr, query_len)
    };
    let Ok(query) = str::from_utf8(query_bytes) else {
        return -2;
    };
    let boosts = if boosts_ptr.is_null() && boosts_count == 0 {
        None
    } else if boosts_ptr.is_null() || boosts_count != index.candidates.len() {
        return -3;
    } else {
        Some(slice::from_raw_parts(boosts_ptr, boosts_count))
    };

    let normalized_query = query.split_whitespace().collect::<Vec<_>>().join(" ");
    let output_limit = result_limit.min(out_capacity);
    let query_is_empty = normalized_query.is_empty();
    let output: Vec<NucleoMatch>;

    if query_is_empty {
        let mut best_matches = BinaryHeap::with_capacity(output_limit);
        for (candidate_index, candidate) in index.candidates.iter().enumerate() {
            append_scored_candidate(
                ScoredCandidate {
                    index: candidate_index,
                    score: candidate_boost(boosts, candidate_index),
                    rank: candidate.rank,
                },
                &mut best_matches,
                output_limit,
            );
        }
        output = sorted_output(best_matches);
    } else {
        let query_mask = ascii_mask_query(&normalized_query);
        let search_tokens = search_tokens(&normalized_query);
        let title_literal = TitleLiteralQuery::new(&normalized_query);
        let mut best_matches = BinaryHeap::with_capacity(output_limit);

        SEARCH_STATE.with(|state| {
            let mut state = state.borrow_mut();
            for (candidate_index, candidate) in index.candidates.iter().enumerate() {
                if candidate.ascii_prefilter_safe {
                    if let Some((query_low, query_high)) = query_mask {
                        if query_low & !candidate.ascii_mask_low != 0
                            || query_high & !candidate.ascii_mask_high != 0
                        {
                            continue;
                        }
                    }
                }

                let Some(score) = weighted_query_score(
                    &mut state,
                    &normalized_query,
                    &search_tokens,
                    &title_literal,
                    candidate,
                ) else {
                    continue;
                };
                append_scored_candidate(
                    ScoredCandidate {
                        index: candidate_index,
                        score: score + candidate_boost(boosts, candidate_index),
                        rank: candidate.rank,
                    },
                    &mut best_matches,
                    output_limit,
                );
            }
        });

        output = sorted_output(best_matches);
    }

    let count = output.len();
    std::ptr::copy_nonoverlapping(output.as_ptr(), out_matches, count);
    *out_count = count;
    0
}

fn candidate_boost(boosts: Option<&[i32]>, candidate_index: usize) -> f64 {
    boosts
        .and_then(|values| values.get(candidate_index))
        .map(|boost| f64::from(*boost))
        .unwrap_or(0.0)
}

fn sorted_output(best_matches: BinaryHeap<WorstFirstScoredCandidate>) -> Vec<NucleoMatch> {
    let mut scored: Vec<ScoredCandidate> = best_matches
        .into_iter()
        .map(|candidate| candidate.0)
        .collect();
    scored.sort_by(scored_candidate_order);
    scored
        .into_iter()
        .map(|candidate| NucleoMatch {
            index: candidate.index,
            score: candidate.score,
            rank: candidate.rank,
        })
        .collect()
}

fn append_scored_candidate(
    candidate: ScoredCandidate,
    best_matches: &mut BinaryHeap<WorstFirstScoredCandidate>,
    output_limit: usize,
) {
    if best_matches.len() < output_limit {
        best_matches.push(WorstFirstScoredCandidate(candidate));
        return;
    }

    let Some(worst_candidate) = best_matches.peek() else {
        return;
    };
    if scored_candidate_order(&candidate, &worst_candidate.0) != Ordering::Less {
        return;
    }
    best_matches.pop();
    best_matches.push(WorstFirstScoredCandidate(candidate));
}

fn text_from_blob(blob: &[u8], offset: usize, len: usize) -> Option<&str> {
    let end = offset.checked_add(len)?;
    if end > blob.len() {
        return None;
    }
    str::from_utf8(&blob[offset..end]).ok()
}

fn search_tokens(query: &str) -> Vec<SearchToken> {
    query
        .split_whitespace()
        .map(|token| SearchToken {
            text: token.to_owned(),
            pattern: Pattern::new(
                token,
                CaseMatching::Ignore,
                Normalization::Smart,
                AtomKind::Fuzzy,
            ),
            initialism_query: initialism_query(token),
        })
        .collect()
}

fn weighted_query_score(
    state: &mut SearchState,
    query: &str,
    tokens: &[SearchToken],
    title_literal: &TitleLiteralQuery,
    candidate: &Candidate,
) -> Option<f64> {
    let token_score = token_sum_score(state, query, tokens, candidate);

    match (
        token_score,
        title_literal_score(state, title_literal, candidate),
    ) {
        (Some(token), Some(literal)) => Some(token.max(literal)),
        (Some(token), None) => Some(token),
        (None, Some(literal)) => Some(literal),
        (None, None) => None,
    }
} 

fn token_sum_score(
    state: &mut SearchState,
    query: &str,
    tokens: &[SearchToken],
    candidate: &Candidate,
) -> Option<f64> {
    if tokens.len() == 1 {
        return weighted_token_score(state, &tokens[0], candidate);
    }

    let mut total_score = 0.0;
    for token in tokens {
        total_score += weighted_token_score(state, token, candidate)?;
    }

    if let Some(exact_query_line_score) = exact_search_text_line_score(candidate, query) {
        total_score = total_score.max(exact_query_line_score);
    }
    Some(total_score)
}

fn weighted_token_score(
    state: &mut SearchState,
    token: &SearchToken,
    candidate: &Candidate,
) -> Option<f64> {
    let title_score = state.score_text(&token.pattern, &candidate.title);
    let search_score = best_search_line_score(state, &token.pattern, candidate);
    weighted_score(
        &token.text,
        token.initialism_query.as_ref(),
        candidate,
        title_score,
        search_score,
    )
}

fn best_search_line_score(
    state: &mut SearchState,
    pattern: &Pattern,
    candidate: &Candidate,
) -> Option<u32> {
    let mut best_score: Option<u32> = None;
    for line in &candidate.search_lines {
        if line.trim().is_empty() {
            continue;
        }
        if let Some(score) = state.score_text(pattern, line) {
            best_score = Some(best_score.map_or(score, |best| best.max(score)));
        }
    }
    best_score
}
