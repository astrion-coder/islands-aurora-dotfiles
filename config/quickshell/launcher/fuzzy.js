.pragma library

// fzf-style fuzzy matching for the launcher. Space-separated words must all match
// (in any order); within a word, its characters must appear in order. Matches at word
// starts and runs of consecutive characters score higher, gaps and long text lower.

function isBoundary(text, i) {
    if (i === 0)
        return true;
    const prev = text[i - 1], cur = text[i];
    return /[\s_\-./\\:()\[\],+@]/.test(prev) || (cur !== cur.toLowerCase() && prev === prev.toLowerCase());
}

function scoreOf(text, positions) {
    let score = 0;
    for (let n = 0; n < positions.length; n++) {
        const pos = positions[n];
        score += 16;
        if (isBoundary(text, pos))
            score += 10;
        if (n > 0) {
            const gap = pos - positions[n - 1] - 1;
            score += gap === 0 ? 12 : -Math.min(gap, 8);
        }
    }
    if (positions[0] === 0)
        score += 8;
    return score - Math.min(positions[0], 10) * 0.5 - text.length * 0.05;
}

// One word against one text: { score, positions } or null.
function matchWord(word, text) {
    const p = word.toLowerCase(), t = text.toLowerCase();
    let best = null;
    let starts = 0;
    for (let start = t.indexOf(p[0]); start !== -1 && starts < 24; start = t.indexOf(p[0], start + 1), starts++) {
        // two ways through: the first occurrence of each character, or the next word start
        for (const preferBoundary of [false, true]) {
            const positions = [start];
            let k = start + 1;
            for (let i = 1; i < p.length; i++) {
                let pos = -1, first = -1;
                for (let x = k; x < t.length; x++) {
                    if (t[x] !== p[i])
                        continue;
                    if (first < 0)
                        first = x;
                    if (!preferBoundary || x === k || isBoundary(text, x)) {
                        pos = x;
                        break;
                    }
                }
                if (pos < 0)
                    pos = first;
                if (pos < 0)
                    break;
                positions.push(pos);
                k = pos + 1;
            }
            if (positions.length < p.length)
                continue;
            const score = scoreOf(text, positions);
            if (!best || score > best.score)
                best = { score, positions };
        }
    }
    return best;
}

// Filter and rank `items` for `query`. Each item has `title` (shown, highlighted) and
// optionally `meta` (hidden keywords, matched with a lower score; exact keywords count
// fully), and may have a `boost`. Returns at most `limit` new objects with `positions`
// (matched characters of the title), best first; an empty query keeps the order.
function filter(items, query, limit) {
    limit = limit || 1000;
    const words = query.trim().split(/\s+/).filter(w => w);
    if (words.length === 0)
        return items.slice(0, limit).map(item => Object.assign({}, item, { positions: [] }));
    const out = [];
    for (let i = 0; i < items.length; i++) {
        const item = items[i];
        let score = 0;
        const positions = [];
        let ok = true;
        for (const word of words) {
            const m = matchWord(word, item.title);
            if (m) {
                score += m.score;
                positions.push(...m.positions);
                continue;
            }
            // hidden keywords: each one on its own (no matches spanning two keywords)
            if (item.meta && !item._keywords)
                item._keywords = item.meta.split(/\s*\|\s*|\s+/).filter(k => k);
            let k = null, exact = false;
            for (const keyword of item._keywords || []) {
                const m = matchWord(word, keyword);
                if (m && (!k || m.score > k.score)) {
                    k = m;
                    exact = keyword.length === word.length;
                }
            }
            if (!k) {
                ok = false;
                break;
            }
            // an exact keyword ("lol") counts like a name match
            score += k.score * (exact ? 1.05 : 0.6);
        }
        if (ok)
            out.push({ item, score: score + (item.boost || 0), index: i, positions });
    }
    out.sort((a, b) => b.score - a.score || a.index - b.index);
    return out.slice(0, limit).map(r => Object.assign({}, r.item, { positions: r.positions }));
}

// Matched characters only, keeping the given order (when fzf has done the ranking).
function mark(items, query) {
    const words = query.trim().split(/\s+/).filter(w => w);
    return items.map(item => {
        const positions = [];
        for (const word of words) {
            const m = matchWord(word, item.title);
            if (m)
                positions.push(...m.positions);
        }
        return Object.assign({}, item, { positions });
    });
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Rich text with the matched characters in `color`, bold.
function highlight(text, positions, color) {
    if (!positions || positions.length === 0)
        return escape(text);
    const marked = new Set(positions);
    let out = "", open = false;
    for (let i = 0; i < text.length; i++) {
        const m = marked.has(i);
        if (m && !open)
            out += `<font color="${color}"><b>`;
        if (!m && open)
            out += "</b></font>";
        open = m;
        out += escape(text[i]);
    }
    return out + (open ? "</b></font>" : "");
}
