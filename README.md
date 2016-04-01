
# Chart of Oweage

Sometimes you need to keep track of costs between people.
This script does that.

## Initializing

Using this as a single person is easy.
The following commands download the script and create a database called `housemates`.

```
curl https://raw.githubusercontent.com/grencez/oweage/master/oweage.sh -o ~/bin/oweage
chmod +x ~/bin/oweage
oweage create housemates
oweage use housemates
```

Everything is stored in `~/.oweage`, so you should be able to figure out how to set up a remote "database" if you know git.
Or just use a local database with a shared user account.

## Normal Use

Adding costs among people is easy.
Say Alice shares expenses with Bob and she pays the $50.50 electricity bill.
To add this, commit to the database, and push to the remote database, she would do:

```
oweage A alice 50.50 alice bob
#> Reason?
electric
```

Bob would see that he owes Alice half of this amount by doing:

```
oweage pull
oweage b bob
#> Balance for bob is $-25.25
#> alice $-25.25
```

The `pull` is to pull updates from the remote database if Alice and Bob use one of those.

And after he pays, say $25, it is recorded as:

```
oweage A bob 25 alice
#> Reason?
paying back
```

Now Alice would see that they are roughly even.

```
oweage pull
oweage b alice
#> Balance for alice is $.25
#> bob $.25
```

