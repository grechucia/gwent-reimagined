ObjC.import('Foundation');

function run(argv) {
    var game = argv[0], out = argv[1];
    function rd(p) { return $.NSString.stringWithContentsOfFileEncodingError(game + '/' + p, 4, null).js; }
    function wr(name, obj) {
        var s = $(JSON.stringify(obj, null, 1));
        s.writeToFileAtomicallyEncodingError(out + '/' + name, true, 4, null);
    }
    var window = this, document = { getElementById: function () { return null; }, addEventListener: function () {} };
    var navigator = { userAgent: '' }, localStorage = { getItem: function () { return null; } };

    var src = [rd('cards.js'), rd('abilities.js'), rd('factions.js'), rd('decks.js')].join('\n;\n').replace(/"use strict"/g, '');
    var R = eval(src + '\n;({cards: card_dict, decks: default_decks, abilities: ability_dict, factions: factions});');
    var cards = {};
    Object.keys(R.cards).forEach(function (k) {
        var c = R.cards[k], o = {};
        Object.keys(c).forEach(function (f) { if (typeof c[f] !== 'function') o[f] = c[f]; });
        cards[k] = o;
    });
    function plain(dict) {
        var o = {};
        Object.keys(dict).forEach(function (k) {
            var e = dict[k], r = {};
            Object.keys(e).forEach(function (f) { var v = e[f]; if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') r[f] = v; });
            o[k] = r;
        });
        return o;
    }
    wr('cards.json', cards);
    wr('decks.json', R.decks);
    wr('abilities.json', plain(R.abilities));
    wr('factions.json', plain(R.factions));
    ['en', 'pl'].forEach(function (code) {
        var t = rd('lang/' + code + '.js');
        var json = t.slice(t.indexOf('= {') + 2).replace(/;\s*$/, '');
        wr('lang_' + code + '.json', JSON.parse(json));
    });
    return 'kart: ' + Object.keys(cards).length + ', talii: ' + R.decks.length + ', umiejętności: ' +
        Object.keys(R.abilities).length + ', frakcji: ' + Object.keys(R.factions).length;
}
