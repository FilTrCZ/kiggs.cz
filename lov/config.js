/**
 * Paw Trail (Kiggs × Pobar) — konfigurace rozhlednového lovu
 *
 * 1) Výchozí stav před napojením Supabase:
 *    - Tlačítko Paw Trail na hlavní stránce je ZAMČENÉ (DEFAULT_TRAIL_ENABLED = false).
 *    - V lokálním režimu si ho můžeš kdykoliv odemknout/zamknout přes lov/admin.html
 *      (ukládá se do localStorage pro testování na tvém zařízení).
 *
 * 2) Online režim (dálkové spuštění z administrace + žebříček + FTF):
 *    - Založ zdarma projekt na https://supabase.com
 *    - Nech zapnutou registraci pro hráče (admin přístup řídí tabulka public.admin_users)
 *    - V SQL Editoru spusť lov/supabase-setup.sql (a přidej svůj e-mail do admin_users)
 *    - Vyplň níže SUPABASE_URL a SUPABASE_ANON_KEY (Project Settings -> API)
 */
window.KIGGS_LOV_CONFIG = {
    GAME_NAME: "Paw Trail",
    GAME_CREATORS: "Kiggs × Pobar",
    SITE_URL: "https://kiggs.cz/lov/",
    SUPABASE_URL: "https://kbkgjfjorkcfffwrjatc.supabase.co",
    SUPABASE_ANON_KEY: "sb_publishable_zZ4iEteRLSGtsKi6UTnVTg_YVBfdfst",
    GPS_RADIUS_METERS: 300,
    DEFAULT_TRAIL_ENABLED: false,
    DEFAULT_TEASER_MESSAGE: "Paw Trail (Kiggs × Pobar) startuje už brzy 🐾",

    // Ukázkové rozhledny pro lokální demo režim (v online režimu se načítají ze Supabase).
    // V kódu jsou pouze SHA-256 hashe tajných kódů, nikdy samotné kódy!
    DEMO_SPOTS: [
        {
            id: "babi-lom",
            name: "Rozhledna Babí lom",
            region: "Jihomoravský kraj",
            elevation: 521,
            lat: 49.3089,
            lng: 16.5784,
            hint: "Hledej poblíž vstupního zábradlí nebo infotabule pod vyhlídkou.",
            secret_note: "Parádní výstup po hřebeni! Pozdravují Kiggs × Pobar 🐾",
            code_hash: "a6639fac08a3c6e8af7c10b9dc6c540b0fb844a1cc7aef55054458713b419f9b"
        },
        {
            id: "holedna",
            name: "Rozhledna Holedná",
            region: "Brno-město",
            elevation: 391,
            lat: 49.2039,
            lng: 16.5338,
            hint: "V oboře kolem divočáků — nálepka čeká dole u konstrukce.",
            secret_note: "Tuhle ocelovou krásku máme hned za rohem. Woof! 🌲",
            code_hash: "d8a8751ecf7b973bad12f39bf23bc825f0feb391087663f0c74cf41673d5ea7d"
        },
        {
            id: "akatova-vez",
            name: "Akátová věž (Výhon)",
            region: "Jihomoravský kraj",
            elevation: 355,
            lat: 49.0419,
            lng: 16.6392,
            hint: "Na vrcholu Výhonu u Židlochovic — mrkni u dřevěného sloupu.",
            secret_note: "Výhled na Pálavu jak z pohlednice. Zasluhuješ piškot! 🦴",
            code_hash: "61e35eb778136e1ed580f3471457fb564254a8f8a7864f9d684ea2d05e710739"
        },
        {
            id: "jurkovicova",
            name: "Jurkovičova rozhledna",
            region: "Zlínský kraj",
            elevation: 480,
            lat: 49.4556,
            lng: 18.1492,
            hint: "Nad Rožnovem na Karlově kopci — pohádková dřevěná stavba.",
            secret_note: "Jedna z nejhezčích rozhleden v Česku! Skvělý úlovek 🏆",
            code_hash: "e2624cd5c7cbf3fedf907bab0c3d1948bb7b88fd2d75c356f4826fdd6ae9f59d"
        }
    ]
};

// Bezpečný SHA-256 hash s fallbackem pro lokální otevření přes file:/// (kde chybí crypto.subtle)
window.kiggsSha256 = async function (input) {
    const str = String(input).trim();
    if (window.crypto && window.crypto.subtle) {
        const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
        return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
    }
    const bytes = new TextEncoder().encode(str);
    const k = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ];
    let h0=0x6a09e667,h1=0xbb67ae85,h2=0x3c6ef372,h3=0xa54ff53a,h4=0x510e527f,h5=0x9b05688c,h6=0x1f83d9ab,h7=0x5be0cd19;
    const bitLen = bytes.length * 8;
    const paddedLen = (((bytes.length + 9) + 63) >> 6) << 6;
    const msg = new Uint8Array(paddedLen);
    msg.set(bytes);
    msg[bytes.length] = 0x80;
    const view = new DataView(msg.buffer);
    view.setUint32(paddedLen - 8, Math.floor(bitLen / 0x100000000), false);
    view.setUint32(paddedLen - 4, bitLen >>> 0, false);
    const w = new Int32Array(64);
    const rotr = (n, x) => (x >>> n) | (x << (32 - n));
    for (let i = 0; i < paddedLen; i += 64) {
        for (let j = 0; j < 16; j++) w[j] = view.getInt32(i + j * 4, false);
        for (let j = 16; j < 64; j++) {
            const s0 = rotr(7, w[j-15]) ^ rotr(18, w[j-15]) ^ (w[j-15] >>> 3);
            const s1 = rotr(17, w[j-2]) ^ rotr(19, w[j-2]) ^ (w[j-2] >>> 10);
            w[j] = (w[j-16] + s0 + w[j-7] + s1) | 0;
        }
        let a=h0,b=h1,c=h2,d=h3,e=h4,f=h5,g=h6,h=h7;
        for (let j = 0; j < 64; j++) {
            const S1 = rotr(6, e) ^ rotr(11, e) ^ rotr(25, e);
            const ch = (e & f) ^ (~e & g);
            const t1 = (h + S1 + ch + k[j] + w[j]) | 0;
            const S0 = rotr(2, a) ^ rotr(13, a) ^ rotr(22, a);
            const maj = (a & b) ^ (a & c) ^ (b & c);
            const t2 = (S0 + maj) | 0;
            h=g; g=f; f=e; e=(d+t1)|0; d=c; c=b; b=a; a=(t1+t2)|0;
        }
        h0=(h0+a)|0; h1=(h1+b)|0; h2=(h2+c)|0; h3=(h3+d)|0;
        h4=(h4+e)|0; h5=(h5+f)|0; h6=(h6+g)|0; h7=(h7+h)|0;
    }
    return [h0,h1,h2,h3,h4,h5,h6,h7].map((v) => (v >>> 0).toString(16).padStart(8, "0")).join("");
};
