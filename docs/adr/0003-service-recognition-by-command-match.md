# Integrations recognize Services by command match

An integration claims any Service whose command matches its own, regardless of who created it or what it is named: a hand-made service running `t3 serve` gets the full T3 controls. Client-side "the app created this" records were rejected because they break on reinstall and on a second device, and reserved names or marker env-vars were rejected because recognition must be general and one integration must recognize several instances distinguished only by working directory. Accepted cost: command-match false positives receive first-party UI.
