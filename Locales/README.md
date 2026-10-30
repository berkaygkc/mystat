# Translating mystat

Every piece of text mystat shows lives in this folder, one JSON file per language. English (`en.json`) is the default and the fallback: if a key is missing in your language, the English text is shown instead.

## Add a language

1. Copy `en.json` to `<code>.json`, where `<code>` is the language code (`de`, `fr`, `pt-BR`, `zh-Hans`, …). mystat picks it automatically when it matches one of the languages in System Settings → General → Language & Region.
2. Fill in `_meta` (see below).
3. Translate the values. Keep the keys as they are.
4. Run the checks:

   ```sh
   swift test --filter LocaleFilesTests
   ```

   They fail if a key is missing or extra, or if a placeholder differs from English.
5. Look at every screen in your language and fix text that overflows or gets cut off:

   ```sh
   tools/lang-gallery.sh <code>    # images in build/lang-gallery/<code>/
   ```

6. Open a pull request.

## `_meta`

| Field | Example (en) | Meaning |
|---|---|---|
| `name` | `English` | The language's name in itself; shown in the language menu. |
| `locale` | `en_US` | Locale for number and date formatting. |
| `plural` | `one` | Plural rule: `one` (1 → `.one`, else `.other`), `zero-one` (0 and 1 → `.one`), `none` (always `.other`). |
| `percent` | `{value}%` | Where the percent sign goes. |
| `dateLine` | `EEEE, MMMM d, y` | Long date in the monitor window, as a [date format pattern](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table). |
| `menubarDate` | `EEE, MMM d, y` | Short date in the menu bar, with three-letter month and weekday names. |
| `dateTemplate` | `Wed, May 13, 2026` | The widest `menubarDate` in your language; the menu bar reserves this much room so it doesn't jump. The tests check it against every date of three years. |
| `timeTemplate` | `88:88` | Same for the clock. |

## Placeholders

`{name}` is replaced with a value, for example `"{free} GB free"`. Keep every placeholder from the English text; you can move it anywhere in the sentence.

Headline keys contain `{emph}`: that part is highlighted in color.

Some placeholders carry a modifier after `|`, such as `{used|poss3}`. Modifiers add grammatical suffixes for one language (today only Turkish uses them) and are ignored elsewhere. Write the placeholder without the modifier unless your language defines one.

## Plurals

Keys ending in `.one` and `.other` are the singular and plural forms, chosen by the `plural` rule in `_meta`. `{n}` is the number. If your language has no singular form after numbers, set `"plural": "none"` and write only the `.other` keys.
