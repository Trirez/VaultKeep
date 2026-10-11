use std::{env, process::ExitCode};

use vaultkeep_core::{generate_password, EntryInput, PasswordPolicy, Vault, VaultError};
use zeroize::Zeroizing;

const USAGE: &str = "usage:
  vaultkeep <vault.kdbx> init
  vaultkeep <vault.kdbx> add <title> <username> [url]   (password generated)
  vaultkeep <vault.kdbx> list [query]
  vaultkeep <vault.kdbx> show <title-query>             (prints password)
  vaultkeep <vault.kdbx> rm <title-query>
  vaultkeep gen [length]";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), VaultError> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("gen") {
        let mut p = PasswordPolicy::default();
        if let Some(n) = args.get(1).and_then(|s| s.parse().ok()) {
            p.length = n;
        }
        println!("{}", generate_password(&p)?);
        return Ok(());
    }
    let (Some(path), Some(cmd)) = (args.first(), args.get(1)) else {
        eprintln!("{USAGE}");
        return Ok(());
    };

    if cmd == "init" {
        let pw = Zeroizing::new(rpassword::prompt_password("New master password: ")?);
        let again = Zeroizing::new(rpassword::prompt_password("Repeat: ")?);
        if *pw != *again {
            eprintln!("passwords do not match");
            return Ok(());
        }
        Vault::create(path, &pw)?;
        println!("created {path}");
        return Ok(());
    }

    let pw = Zeroizing::new(rpassword::prompt_password("Master password: ")?);
    let mut vault = Vault::open(path, &pw)?;
    let arg = |i: usize| args.get(i).cloned().unwrap_or_default();

    match cmd.as_str() {
        "add" => {
            let input = EntryInput {
                title: arg(2),
                username: arg(3),
                url: arg(4),
                password: generate_password(&PasswordPolicy::default())?.into(),
                ..Default::default()
            };
            vault.add(&input)?;
            vault.save()?;
            println!("added '{}'", input.title);
        }
        "list" => {
            for e in vault.search(&arg(2)) {
                println!("{}  {}  {}", e.title, e.username, e.url);
            }
        }
        "show" => match vault.search(&arg(2)).first() {
            Some(e) => println!("{}", *vault.password(e.id)?),
            None => eprintln!("no match"),
        },
        "rm" => match vault.search(&arg(2)).first() {
            Some(e) => {
                vault.remove(e.id)?;
                vault.save()?;
                println!("removed '{}'", e.title);
            }
            None => eprintln!("no match"),
        },
        _ => eprintln!("{USAGE}"),
    }
    Ok(())
}
