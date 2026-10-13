# Regret - Zig Application

Find out what an amount of a coin would be worth at its peak USD price since a given date, and how much you "wasted" by spending it since then. Prices come from the Coinbase Exchange API.

## Usage

```
regret AMOUNT COIN DATE [FIAT] [--datefmt FMT] [--tz TZ]
```

| Argument | Description |
| --- | --- |
| `AMOUNT` | How much of the coin you held. Must be a positive number. |
| `COIN` | The coin symbol, e.g. `BTC`, `ETH` (case-insensitive). |
| `DATE` | When you bought the coins. Interpreted as midnight in `--tz`. Must be in the past. |
| `FIAT` | Currency to show results in. Default: `USD`. |
| `--datefmt FMT` (alias `--dateformat`) | Input date format, e.g. `MM/DD/YYYY`, `mm/dd/yy`, `MM/DD` (assumes current year). Default: `MM/DD/YYYY`. |
| `--tz TZ` (alias `--timezone`) | IANA timezone for the date, e.g. `America/New_York`. Default: system timezone. |

### Examples

```sh
regret 0.5 BTC 01/15/2021
regret 10 eth 2021-05-01 --datefmt YYYY-MM-DD
regret 1000 doge 03/01 EUR --tz Europe/Berlin
```

### Output

```
Coin:             BTC
Amount:           0.5 BTC
Since:            01/15/2021
Price at date:    <price> USD //price of 1 BTC on <day>
Value at date:    <value> USD
Highest price:    <price> USD //price of 1 BTC on <day>
Value at peak:    <value> USD
Current value:    <value> USD (@ <price> USD)
Missed profits:   <peak value minus value at date> USD
```

- **Price at date** uses the closing price of the first daily candle on or after your date.
- **Highest price** is the highest daily high since your date.
- **Current value** uses the close of the most recent daily candle.
- **Missed profits** is the value at peak minus the value at your date.

## How it works

1. Arguments are parsed and the date is converted to local midnight in the chosen timezone (DST-aware).
2. Daily candles are fetched from `https://api.exchange.coinbase.com/products/{COIN}-{FIAT}/candles` in chunks of up to 300 days, with a short delay between requests to stay polite to the API.
3. Candles are folded into a summary (peak, price at date, latest), which is printed as a report.

## Project layout

```
src/
  main.zig                 entry point
  app/
    ArgumentParser.zig     CLI arguments
    Report.zig             report formatting
  api/
    Coinbase.zig           Coinbase candles client
  types/
    Candle.zig             daily candle (time, high, close)
    Summary.zig            peak / since / latest tracking
    Span.zig, Chunks.zig   time ranges and request chunking
    Currency.zig           money formatting (thousands separators, 2 decimals)
  utils/
    time_util.zig          timezone loading, local midnight, ISO dates
    date.zig               custom date-format parser
    crash_util.zig         fatal error helper
```

## Dependencies

- [`zeit`](https://github.com/rockorager/zeit/tree/b1c1c2fcbc71fd7799a316bbcf0ff88d06d80ccc) for timezone and date handling. **zeit is patched in this project** (see below).
- [`args`](https://github.com/muhammad-fiaz/args.zig/tree/7d4fa8ea18641f6de85d57bce8685cc49e1a3991) for command-line argument parsing.

## Note: Zeit is patched

This project builds against a **patched version of `zeit`**. The patches are applied to the dependency as part of the build, which modifies files in the working tree.

> [!WARNING]
> Run `zig build clean` **before every commit** to clean the tree.
> This reverts the patched files so the patches don't get committed by accident.

```sh
zig build clean
```

## Error messages

<details>
<summary>Show all error messages</summary>

| Message | Cause |
| --- | --- |
| `Unknown timezone: ...` | `--tz` isn't a valid IANA name. |
| `Invalid date "..." for format ...` | `DATE` doesn't match `--datefmt`, or isn't a real calendar date. |
| `Date must be in the past.` | `DATE` is now or in the future. |
| `Could not find a market for: COIN-FIAT` | Coinbase has no such trading pair. |
| `Coinbase API error: ...` | Coinbase returned a non-OK HTTP status. |
| `No price data found ...` | No candles returned for that coin since the date. |

</details>
