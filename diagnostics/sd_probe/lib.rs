#![no_std]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Transport,
    Response(u8),
    Timeout,
    Voltage,
    Unsupported,
    Token(u8),
    Crc,
}
pub trait Bus {
    fn select(&mut self, active: bool) -> Result<(), Error>;
    fn transfer(&mut self, tx: u8) -> Result<u8, Error>;
    fn delay_ms(&mut self, ms: u32);
}
pub fn crc16(data: &[u8]) -> u16 {
    let mut c: u16 = 0;
    for &b in data {
        c ^= (b as u16) << 8;
        for _ in 0..8 {
            if c & 0x8000 != 0 {
                c = (c << 1) ^ 0x1021;
            } else {
                c <<= 1;
            }
        }
    }
    c
}
fn cleanup<B: Bus>(b: &mut B) -> Result<(), Error> {
    let s = b.select(false);
    let t = b.transfer(0xFF).map(|_| ());
    match (s, t) {
        (Ok(_), Ok(_)) => Ok(()),
        (Err(e), _) => Err(e),
        (_, Err(e)) => Err(e),
    }
}
fn cmd<B: Bus>(b: &mut B, n: u8, arg: u32, crc: u8) -> Result<u8, Error> {
    b.select(false)?;
    b.transfer(0xFF)?;
    b.select(true)?;
    b.transfer(0xFF)?;
    let f = [
        0x40 | n,
        (arg >> 24) as u8,
        (arg >> 16) as u8,
        (arg >> 8) as u8,
        arg as u8,
        crc,
    ];
    for &x in &f {
        b.transfer(x)?;
    }
    for _ in 0..16 {
        let r = b.transfer(0xFF)?;
        if r & 0x80 == 0 {
            return Ok(r);
        }
    }
    Err(Error::Timeout)
}
fn rd<B: Bus>(b: &mut B, o: &mut [u8]) -> Result<(), Error> {
    for v in o.iter_mut() {
        *v = b.transfer(0xFF)?;
    }
    Ok(())
}
pub fn init<B: Bus>(b: &mut B) -> Result<u32, Error> {
    let r = inner_init(b);
    match r {
        Ok(v) => cleanup(b).map(|_| v),
        Err(e) => {
            let _ = cleanup(b);
            Err(e)
        }
    }
}
fn inner_init<B: Bus>(b: &mut B) -> Result<u32, Error> {
    b.delay_ms(1);
    b.select(false)?;
    for _ in 0..10 {
        b.transfer(0xFF)?;
    }
    let mut ok = false;
    for _ in 0..10 {
        match cmd(b, 0, 0, 0x95) {
            Ok(1) => {
                ok = true;
                break;
            }
            Ok(v) => return Err(Error::Response(v)),
            Err(Error::Timeout) => {
                b.delay_ms(1);
            }
            Err(e) => return Err(e),
        }
    }
    if !ok {
        return Err(Error::Timeout);
    }
    let r = cmd(b, 8, 0x1AA, 0x87)?;
    if r != 1 {
        return Err(Error::Response(r));
    }
    let mut e = [0u8; 4];
    rd(b, &mut e)?;
    if e != [0, 0, 1, 0xAA] {
        return Err(Error::Voltage);
    }
    let mut ready = false;
    for _ in 0..2000 {
        let c = cmd(b, 55, 0, 0x01)?;
        if c != 0 && c != 1 {
            return Err(Error::Response(c));
        }
        match cmd(b, 41, 0x40000000, 0x01)? {
            0 => {
                ready = true;
                break;
            }
            1 => b.delay_ms(1),
            v => return Err(Error::Response(v)),
        }
    }
    if !ready {
        return Err(Error::Timeout);
    }
    let r = cmd(b, 58, 0, 0x01)?;
    if r != 0 {
        return Err(Error::Response(r));
    }
    let mut o = [0u8; 4];
    rd(b, &mut o)?;
    let v = u32::from_be_bytes(o);
    if v & (1 << 31) == 0 {
        return Err(Error::Voltage);
    }
    if v & (1 << 30) == 0 {
        return Err(Error::Unsupported);
    }
    if v & ((1 << 20) | (1 << 21)) == 0 {
        return Err(Error::Voltage);
    }
    Ok(v)
}
pub fn read_block0<B: Bus>(b: &mut B, d: &mut [u8; 512]) -> Result<u16, Error> {
    let r = inner_read(b, d);
    match r {
        Ok(v) => cleanup(b).map(|_| v),
        Err(e) => {
            let _ = cleanup(b);
            Err(e)
        }
    }
}
fn inner_read<B: Bus>(b: &mut B, d: &mut [u8; 512]) -> Result<u16, Error> {
    let r = cmd(b, 17, 0, 0x01)?;
    if r != 0 {
        return Err(Error::Response(r));
    }
    let mut found = false;
    for _ in 0..12500 {
        let x = b.transfer(0xFF)?;
        if x == 0xFF {
            continue;
        }
        if x == 0xFE {
            found = true;
            break;
        }
        return Err(Error::Token(x));
    }
    if !found {
        return Err(Error::Timeout);
    }
    for v in d.iter_mut() {
        *v = b.transfer(0xFF)?;
    }
    let h = b.transfer(0xFF)?;
    let l = b.transfer(0xFF)?;
    let card = ((h as u16) << 8) | l as u16;
    if crc16(d) != card {
        return Err(Error::Crc);
    }
    Ok(card)
}
#[cfg(test)]
extern crate std;
#[cfg(test)]
mod tests;
