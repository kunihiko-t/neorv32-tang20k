use super::*;
use std::collections::VecDeque;
use std::vec::Vec;

struct Fake {
    cs: bool,
    tx: Vec<(bool, u8)>,
    sel: Vec<bool>,
    rx: VecDeque<u8>,
    fail: Option<usize>,
    n: usize,
    frame_left: usize,
    responding: bool,
}
impl Fake {
    fn new() -> Self {
        Self {
            cs: false,
            tx: Vec::new(),
            sel: Vec::new(),
            rx: VecDeque::new(),
            fail: None,
            n: 0,
            frame_left: 0,
            responding: false,
        }
    }
    fn push(&mut self, b: &[u8]) {
        for &x in b {
            self.rx.push_back(x);
        }
    }
    // Record command frames seen while CS asserted (active=true means CS low).
    // Data/idle polls are tx==0xFF so they are skipped, never misidentified.
    fn frames(&self) -> Vec<Vec<u8>> {
        let mut s: Vec<u8> = Vec::new();
        for (c, b) in self.tx.iter() {
            if *c {
                s.push(*b);
            }
        }
        let mut out: Vec<Vec<u8>> = Vec::new();
        let mut i = 0;
        while i < s.len() {
            if s[i] == 0xFF {
                i += 1;
                continue;
            }
            if s[i] & 0xC0 == 0x40 && i + 6 <= s.len() {
                let mut v: Vec<u8> = Vec::new();
                for k in 0..6 {
                    v.push(s[i + k]);
                }
                out.push(v);
                i += 6;
            } else {
                i += 1;
            }
        }
        out
    }
    fn cmds(&self) -> Vec<u8> {
        let mut v: Vec<u8> = Vec::new();
        for f in self.frames().iter() {
            v.push(f[0] & 0x3F);
        }
        v
    }
    fn allowed(&self) {
        for c in self.cmds().iter() {
            assert!(
                c == &0 || c == &8 || c == &55 || c == &41 || c == &58 || c == &17,
                "forbidden {}",
                c
            );
        }
    }
}
impl Bus for Fake {
    fn select(&mut self, a: bool) -> Result<(), Error> {
        self.frame_left = 0;
        self.responding = false;
        self.cs = a;
        self.sel.push(a);
        Ok(())
    }
    fn transfer(&mut self, tx: u8) -> Result<u8, Error> {
        if self.fail == Some(self.n) {
            self.n += 1;
            self.tx.push((self.cs, tx));
            return Err(Error::Transport);
        }
        self.n += 1;
        self.tx.push((self.cs, tx));
        if !self.cs {
            return Ok(0xFF);
        }
        // The card cannot respond before receiving all six command bytes.
        if self.frame_left > 0 {
            self.frame_left -= 1;
            self.responding = self.frame_left == 0;
            return Ok(0xFF);
        }
        if !self.responding {
            if tx & 0xC0 == 0x40 {
                self.frame_left = 5;
            } else {
                assert_eq!(tx, 0xFF, "idle clocks must hold MOSI high");
            }
            return Ok(0xFF);
        }
        assert_eq!(tx, 0xFF, "receive must hold MOSI high");
        Ok(self.rx.pop_front().unwrap_or(0xFF))
    }
    fn delay_ms(&mut self, _ms: u32) {}
}

#[test]
fn crc_vector() {
    assert_eq!(crc16(b"123456789"), 0x31C3);
}

#[test]
fn crc_zeros() {
    assert_eq!(crc16(&[0u8; 512]), 0x0000);
}

#[test]
fn init_ok() {
    let mut f = Fake::new();
    f.push(&[
        0x01, 0x01, 0, 0, 1, 0xAA, 0x01, 0x00, 0x00, 0xC0, 0xFF, 0x80, 0x00,
    ]);
    assert_eq!(init(&mut f).unwrap(), 0xC0FF8000);
    f.allowed();
    let fr = f.frames();
    assert_eq!(fr.len(), 5);
    assert_eq!(fr[0].as_slice(), &[0x40, 0, 0, 0, 0, 0x95]);
    assert_eq!(fr[1].as_slice(), &[0x48, 0, 0, 1, 0xAA, 0x87]);
    assert_eq!(fr[2].as_slice(), &[0x77, 0, 0, 0, 0, 0x01]);
    assert_eq!(fr[3].as_slice(), &[0x69, 0x40, 0, 0, 0, 0x01]);
    assert_eq!(fr[4].as_slice(), &[0x7A, 0, 0, 0, 0, 0x01]);
    assert_eq!(f.sel[0], false);
    assert!(f.sel.contains(&true));
    assert_eq!(*f.sel.last().unwrap(), false);
    assert_eq!(
        f.sel,
        [false, false, true, false, true, false, true, false, true, false, true, false]
    );
    assert!(f.tx.iter().take_while(|(cs, _)| !cs).count() >= 10);
}

#[test]
fn read_ok() {
    let mut f = Fake::new();
    f.push(&[0x00, 0xFF, 0xFE]);
    for _ in 0..512 {
        f.rx.push_back(0);
    }
    f.push(&[0x00, 0x00]);
    let mut d = [0xFFu8; 512];
    assert_eq!(read_block0(&mut f, &mut d).unwrap(), 0x0000);
    assert_eq!(d, [0u8; 512]);
    f.allowed();
    let fr = f.frames();
    assert_eq!(fr.len(), 1);
    assert_eq!(fr[0].as_slice(), &[0x51, 0, 0, 0, 0, 0x01]);
    assert_eq!(*f.sel.last().unwrap(), false);
}

#[test]
fn no_card() {
    let mut f = Fake::new();
    assert_eq!(init(&mut f).unwrap_err(), Error::Timeout);
    f.allowed();
    assert!(!f.frames().is_empty());
    assert_eq!(*f.sel.last().unwrap(), false);
}

#[test]
fn cmd8_mismatch() {
    let mut f = Fake::new();
    f.push(&[0x01, 0x01, 0, 0, 2, 0xAA]);
    assert_eq!(init(&mut f).unwrap_err(), Error::Voltage);
    f.allowed();
    assert_eq!(*f.sel.last().unwrap(), false);
}

#[test]
fn ccs_rejected() {
    let mut f = Fake::new();
    f.push(&[
        0x01, 0x01, 0, 0, 1, 0xAA, 0x01, 0x00, 0x00, 0x80, 0xFF, 0x80, 0x00,
    ]);
    assert_eq!(init(&mut f).unwrap_err(), Error::Unsupported);
    f.allowed();
    assert_eq!(*f.sel.last().unwrap(), false);
}

#[test]
fn never_ready() {
    let mut f = Fake::new();
    f.push(&[0x01, 0x01, 0, 0, 1, 0xAA]);
    for _ in 0..2000 {
        f.rx.push_back(0x01);
        f.rx.push_back(0x01);
    }
    assert_eq!(init(&mut f).unwrap_err(), Error::Timeout);
    f.allowed();
    assert_eq!(f.cmds().len(), 2 + 2 * 2000);
    assert_eq!(*f.sel.last().unwrap(), false);
}

#[test]
fn bad_token() {
    let mut f = Fake::new();
    f.push(&[0x00, 0xFC]);
    let mut d = [0u8; 512];
    assert_eq!(read_block0(&mut f, &mut d).unwrap_err(), Error::Token(0xFC));
    f.allowed();
    assert_eq!(*f.sel.last().unwrap(), false);
}

#[test]
fn bad_crc() {
    let mut f = Fake::new();
    f.push(&[0x00, 0xFF, 0xFE]);
    for _ in 0..512 {
        f.rx.push_back(0);
    }
    f.push(&[0x12, 0x34]);
    let mut d = [0u8; 512];
    assert_eq!(read_block0(&mut f, &mut d).unwrap_err(), Error::Crc);
    assert_eq!(d, [0u8; 512]);
    f.allowed();
}

#[test]
fn transport_cleanup() {
    let mut f = Fake::new();
    f.fail = Some(5); // fail after asserting CS, while sending CMD17
    assert_eq!(read_block0(&mut f, &mut [0; 512]), Err(Error::Transport));
    assert_eq!(*f.sel.last().unwrap(), false);
    assert_eq!(*f.tx.last().unwrap(), (false, 0xFF));
}

#[test]
fn missing_data_token_times_out_and_deselects() {
    let mut f = Fake::new();
    f.push(&[0]);
    assert_eq!(read_block0(&mut f, &mut [0; 512]), Err(Error::Timeout));
    assert_eq!(*f.tx.last().unwrap(), (false, 0xFF));
    assert!(f.n >= 12500 && f.n < 12600);
    assert_eq!(f.cmds(), [17]);
}
