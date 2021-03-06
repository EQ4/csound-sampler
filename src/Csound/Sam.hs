-- | The sampler
{-# Language TypeFamilies, DeriveFunctor, TypeSynonymInstances, FlexibleInstances #-}
module Csound.Sam (
	Sample, Sam, Bpm, runSam, 
	-- * Lifters
	mapBpm, bindSam, bindBpm, liftSam, mapBpm2, bindBpm2, withBpm,
	-- * Constructors
	sig1, sig2, infSig1, infSig2, fromSig1, fromSig2, ToSam(..), limSam,
	-- ** Stereo
	wav, wavr, seg, segr, rndWav, rndWavr, rndSeg, rndSegr, ramWav,
	-- ** Mono
	wav1, wavr1, seg1, segr1, rndWav1, rndWavr1, rndSeg1, rndSegr1, ramWav1,	
	-- * Reading from RAM
	-- ** Stereo
	ramLoop, ramRead, segLoop, segRead, relLoop, relRead,
	-- ** Mono	
	ramLoop1, ramRead1, segLoop1, segRead1, relLoop1, relRead1,
	-- * Envelopes
	linEnv, expEnv, hatEnv, decEnv, riseEnv, edecEnv, eriseEnv,
	-- * Arrange
	wide, flow, pick, pickBy, 
	atPan, atPch, atCps, atPanRnd, atVolRnd, atVolGauss,	
	-- * Loops
	rep1, rep, pat1, pat, pat',	
	-- * Arpeggio
    Chord,
	arpUp, arpDown, arpOneOf, arpFreqOf,
	arpUp1, arpDown1, arpOneOf1, arpFreqOf1,
    -- * Misc patterns
    wall, forAirports, genForAirports, arpy,

    -- * Utils
    metroS, toSec,

    -- * UIs
    module Csound.Sam.Ui,

    -- * Triggering samples
    module Csound.Sam.Trig
) where

import Control.Monad.Trans.Class
import Control.Applicative
import Control.Monad.Trans.Reader

import Csound.Base
import Csound.Sam.Core
import Csound.Sam.Ui
import Csound.Sam.Trig

type instance DurOf Sam = D

instance Melody Sam where
	mel = flow

instance Harmony Sam where
	(=:=) = (+)

instance Compose Sam where

instance Delay Sam where
	del dt = tfmS phi
		where phi bpm x = x { samSig = asig, samDur = dur }
				where 
					absDt = toSec bpm dt
					asig  = delaySnd absDt $ samSig x
					dur   = addDur absDt $ samDur x

instance Stretch Sam where
	str k (Sam a) = Sam $ withReaderT ( * k) a

instance Limit Sam where
	lim d = tfmS $ \bpm x -> 
		let absD = toSec bpm d 
		in  x { samSig = takeSnd absD $ samSig x
			  , samDur = Dur absD }

instance Loop Sam where
	loop = genLoop $ \_ d asig -> repeatSnd d asig

instance Rest Sam where
	rest dt = Sam $ reader $ \bpm -> S 0 (Dur $ toSec bpm dt)

-- | Constructs sample from mono signal
infSig1 :: Sig -> Sam
infSig1 x = pure (x, x)

-- | Constructs sample from stereo signal
infSig2 :: Sig2 -> Sam
infSig2 = pure

-- | Constructs sample from limited mono signal (duration is in seconds)
sig1 :: D -> Sig -> Sam
sig1 dt a = Sam $ reader $ \_ -> S (a, a) (Dur dt)

-- | Constructs sample from limited stereo signal (duration is in seconds)
sig2 :: D -> Sig2 -> Sam
sig2 dt a = Sam $ reader $ \_ -> S a (Dur dt)

-- | Constructs sample from limited mono signal (duration is in BPMs)
fromSig1 :: D -> Sig -> Sam
fromSig1 dt = lim dt . infSig1

-- | Constructs sample from limited stereo signal (duration is in BPMs)
fromSig2 :: D -> Sig2 -> Sam
fromSig2 dt = lim dt . infSig2

-- | Constructs sample from wav or aiff files.
wav :: String -> Sam
wav fileName = Sam $ return $ S (readSnd fileName) (Dur $ lengthSnd fileName)

-- | Constructs sample from wav that is played in reverse.
wavr :: String -> Sam
wavr fileName = Sam $ return $ S (takeSnd len $ loopWav (-1) fileName) (Dur len)
	where len = lengthSnd fileName

-- | Constructs sample from the segment of a wav file. The start and end times are measured in seconds.
--
-- > seg begin end fileName
seg :: D -> D -> String -> Sam
seg start end fileName = Sam $ return $ S (readSegWav start end 1 fileName) (Dur len)
	where len = end - start

--- | Constructs reversed sample from segment of an audio file.
segr :: D -> D -> String -> Sam
segr start end fileName = Sam $ return $ S (readSegWav start end (-1) fileName) (Dur len)
	where len = end - start

-- | Picks segments from the wav file at random. The first argument is the length of the segment.
rndWav :: D -> String -> Sam
rndWav dt fileName = rndSeg dt 0 (lengthSnd fileName) fileName

-- | Picks segments from the wav file at random. The first argument is the length of the segment.
rndWavr :: D -> String -> Sam
rndWavr dt fileName = rndSegr dt 0 (lengthSnd fileName) fileName

-- | Constructs random segments of the given length from an interval.
rndSeg :: D -> D -> D -> String -> Sam
rndSeg = genRndSeg 1

-- | Constructs reversed random segments of the given length from an interval.
rndSegr :: D -> D -> D -> String -> Sam
rndSegr = genRndSeg (-1)

genRndSeg :: Sig -> D -> D -> D -> String -> Sam
genRndSeg speed len start end fileName = Sam $ lift $ do
	x <- random 0 1
	let a = start + dl * x
	let b = a + len
	return $ S (readSegWav a b speed fileName) (Dur len)
	where dl = end - len

-- | Reads a sample from the file in RAM.
--
-- > ramWav loopMode speed fileName
ramWav :: LoopMode -> Sig -> String -> Sam
ramWav loopMode speed fileName = Sam $ return $ S (ramSnd loopMode speed fileName) (Dur $ lengthSnd fileName)

-- | Reads a sample from the mono file in RAM.
--
-- > ramWav1 loopMode speed fileName
ramWav1 :: LoopMode -> Sig -> String -> Sam
ramWav1 loopMode speed fileName = Sam $ return $ S (let x = ramSnd1 loopMode speed fileName in (x, x)) (Dur $ lengthSnd fileName)

-- | Constructs sample from mono wav or aiff files.
wav1 :: String -> Sam
wav1 fileName = Sam $ return $ S (let x = readSnd1 fileName in (x, x)) (Dur $ lengthSnd fileName)

-- | Constructs sample from mono wav that is played in reverse.
wavr1 :: String -> Sam
wavr1 fileName = Sam $ return $ S (let x = takeSnd len $ loopWav1 (-1) fileName in (x, x)) (Dur len)
	where len = lengthSnd fileName

-- | Constructs sample from the segment of a mono wav file. The start and end times are measured in seconds.
--
-- > seg begin end fileName
seg1 :: D -> D -> String -> Sam
seg1 start end fileName = Sam $ return $ S (let x = readSegWav1 start end 1 fileName in (x, x)) (Dur len)
	where len = end - start

--- | Constructs reversed sample from segment of a mono audio file.
segr1 :: D -> D -> String -> Sam
segr1 start end fileName = Sam $ return $ S (let x = readSegWav1 start end (-1) fileName in (x, x)) (Dur len)
	where len = end - start

-- | Picks segments from the mono wav file at random. The first argument is the length of the segment.
rndWav1 :: D -> String -> Sam
rndWav1 dt fileName = rndSeg1 dt 0 (lengthSnd fileName) fileName

-- | Picks segments from the mono wav file at random. The first argument is the length of the segment.
rndWavr1 :: D -> String -> Sam
rndWavr1 dt fileName = rndSegr1 dt 0 (lengthSnd fileName) fileName

-- | Constructs random segments of the given length from an interval.
rndSeg1 :: D -> D -> D -> String -> Sam
rndSeg1 = genRndSeg1 1

-- | Constructs reversed random segments of the given length from an interval.
rndSegr1 :: D -> D -> D -> String -> Sam
rndSegr1 = genRndSeg1 (-1)

genRndSeg1 :: Sig -> D -> D -> D -> String -> Sam
genRndSeg1 speed len start end fileName = Sam $ lift $ do
	x <- random 0 1
	let a = start + dl * x
	let b = a + len
	return $ S (let y = readSegWav1 a b speed fileName in (y, y)) (Dur len)
	where dl = end - len


toSec :: Bpm -> D -> D
toSec bpm a = a * 60 / bpm

toSecSig :: Bpm -> Sig -> Sig
toSecSig bpm a = a * 60 / sig bpm

addDur :: D -> Dur -> Dur
addDur d x = case x of
	Dur a  -> Dur $ d + a
	InfDur -> InfDur

-- | Scales sample by pitch in tones.
atPch :: Sig -> Sam -> Sam
atPch k = mapSig (scalePitch k)

-- | Panning. 0 is all left and 1 is all right.
atPan :: Sig -> Sam -> Sam
atPan k = fmap (\(a, b) -> pan2 (mean [a, b]) k)

-- | Scales sample by pitch in factor of frequency.
atCps :: Sig -> Sam -> Sam
atCps k = mapSig (scaleSpec k)

tfmBy :: (S Sig2 -> Sig2) -> Sam -> Sam
tfmBy f = Sam . fmap (\x -> x { samSig = f x }) . unSam

tfmS :: (Bpm -> S Sig2 -> S Sig2) -> Sam -> Sam
tfmS f ra = Sam $ do
	bpm <- ask
	a <- unSam ra
	return $ f bpm a	

setInfDur :: Sam -> Sam
setInfDur = Sam . fmap (\a -> a { samDur = InfDur }) . unSam

-- | Makes the sampler broader. It's reciprocal of str
--
-- > wide k = str (1 / k)
wide :: D -> Sam -> Sam
wide = str . recip

-- | Plays a list of samples one after another.
flow :: [Sam] -> Sam
flow [] = 0
flow as = foldr1 flow2 as 

flow2 :: Sam -> Sam -> Sam
flow2 (Sam ra) (Sam rb) = Sam $ do
	a <- ra
	b <- rb
	let sa = samSig a
	let sb = samSig b
	return $ case (samDur a, samDur b) of
		(Dur da, Dur db) -> S (sa + delaySnd da sb) (Dur $ da + db)
		(InfDur, _)      -> a
		(Dur da, InfDur) -> S (sa + delaySnd da sb) InfDur

type PickFun = [(D, D)] -> Evt Unit -> Evt (D, D)

genPick :: PickFun -> Sig -> [Sam] -> Sam
genPick pickFun dt as = Sam $ do
	bpm <- ask
	xs <- sequence $ fmap unSam as
	let ds = fmap (getDur . samDur)  xs
	let sigs = fmap samSig xs
	return $ S (sched (\n -> return $ atTuple sigs $ sig n) $ fmap (\(dt, a) -> str dt $ temp a) $ pickFun (zip ds (fmap int [0..])) $ metroS bpm dt) InfDur 
	where getDur x = case x of
			InfDur -> -1
			Dur d  -> d

-- | Picks samples at random. The first argument is the period ofmetronome in BPMs.
-- The tick of metronome produces new random sample from the list.
pick :: Sig -> [Sam] -> Sam
pick = genPick oneOf

-- | Picks samples at random. We can specify a frequency of the occurernce.
-- The sum of all frequencies should be equal to 1.
pickBy :: Sig -> [(D, Sam)] -> Sam
pickBy dt as = genPick (\ds -> freqOf $ zip (fmap fst as) ds) dt (fmap snd as)

type EnvFun = (Dur -> D -> D -> Sig)

genEnv :: EnvFun -> D -> D -> Sam -> Sam
genEnv env start end = tfmS f
	where f bpm a = a { samSig = mul (env (samDur a) absStart absEnd) $ samSig a }
			where 
				absStart = toSec bpm start
				absEnd   = toSec bpm end

-- | A linear rise-decay envelope. Times a given in BPMs.
--
-- > linEnv rise dec sample
linEnv :: D -> D -> Sam -> Sam
linEnv = genEnv f
	where f dur start end = case dur of
			InfDur -> linseg [0, start, 1]
			Dur d  -> linseg [0, start, 1, maxB 0 (d - start - end), 1, end , 0]

-- | An exponential rise-decay envelope. Times a given in BPMs.
--
-- > expEnv rise dec sample
expEnv :: D -> D -> Sam -> Sam
expEnv = genEnv f
	where 
		f dur start end = case dur of
			InfDur -> expseg [zero, start, 1]
			Dur d  -> expseg [zero, start, 1, maxB 0 (d - start - end), 1, end , zero]
		zero = 0.00001

genEnv1 :: (D -> Sig) -> Sam -> Sam
genEnv1 envFun = tfmBy f
	where 
		f a = flip mul (samSig a) $ case samDur a of
			InfDur -> 1
			Dur d  -> envFun d


-- | Parabolic envelope that starts and ends at zero and reaches maximum at the center.
hatEnv :: Sam -> Sam
hatEnv = genEnv1 $ \d -> oscBy (polys 0 1 [0, 1, -1]) (1 / sig d)

-- | Fade in linear envelope.
riseEnv :: Sam -> Sam
riseEnv = genEnv1 $ \d -> linseg [0, d, 1]

-- | Fade out linear envelope.
decEnv :: Sam -> Sam
decEnv = genEnv1 $ \d -> linseg [1, d, 0]

-- | Fade in exponential envelope.
eriseEnv :: Sam -> Sam
eriseEnv = genEnv1 $ \d -> expseg [0.0001, d, 1]

-- | Fade out exponential envelope.
edecEnv :: Sam -> Sam
edecEnv = genEnv1 $ \d -> expseg [1, d, 0.0001]

type LoopFun = D -> D -> Sig2 -> Sig2

genLoop :: LoopFun -> Sam -> Sam 
genLoop g = setInfDur . tfmS f
	where 
		f bpm a = a { samSig = case samDur a of
			InfDur -> samSig a
			Dur d  -> g bpm d (samSig a)
		}


-- | Plays the sample at the given period (in BPMs). The samples don't overlap.
rep1 :: D -> Sam -> Sam
rep1 = rep . return

-- | Plays the sample at the given period (in BPMs). The overlapped samples are mixed together.
pat1 :: D -> Sam -> Sam
pat1 = pat . return

-- | Plays the sample at the given pattern of periods (in BPMs). The samples don't overlap.
rep :: [D] -> Sam -> Sam 
rep dts = genLoop $ \bpm d asig -> sched (const $ return asig) $ fmap (const $ notes bpm d) $ metroS bpm (sig $ sum dts)
	where notes bpm _ = har $ zipWith (\t dt-> singleEvent (toSec bpm t) (toSec bpm dt) unit) (patDurs dts) dts	 
		
-- | Plays the sample at the given pattern of periods (in BPMs). The overlapped samples are mixed together.
pat :: [D] -> Sam -> Sam 
pat dts = genLoop $ \bpm d asig -> sched (const $ return asig) $ fmap (const $ notes bpm d) $ metroS bpm (sig $ sum dts)
	where notes bpm d = har $ fmap (\t -> fromEvent $ Event (toSec bpm t) d unit) $ patDurs dts		

-- | Plays the sample at the given pattern of volumes and periods (in BPMs). The overlapped samples are mixed together.
--
-- > pat' volumes periods
pat' :: [D] -> [D] -> Sam -> Sam 
pat' vols dts = genLoop $ \bpm d asig -> sched (instr asig) $ fmap (const $ notes bpm d) $ metroS bpm (sig $ sum dts')
	where 
		notes bpm d = har $ zipWith (\v t -> singleEvent (toSec bpm t) d v) vols' $ patDurs dts'		
		instr asig v = return $ mul (sig v) asig
		(vols', dts') = unzip $ lcmList vols dts

lcmList :: [a] -> [b] -> [(a, b)]
lcmList as bs = take n $ zip (cycle as) (cycle bs)
	where n = lcm (length as) (length bs)

-- | Constructs the wall of sound from the initial segment of the sample.
-- The segment length is given in BPMs.
--
-- > wall segLength
wall :: D -> Sam -> Sam 
wall dt a = mean [b, del hdt b]
	where 
		hdt = 0.5 * dt
		f = pat1 hdt . hatEnv . lim dt
		b = f a

-- | The tones of the chord.
type Chord = [D]

type Arp1Fun = Evt Unit -> Evt D

arpInstr :: Sig2 -> D -> SE Sig2
arpInstr asig k = return $ mapSig (scalePitch (sig k)) asig 

patDurs :: [D] -> [D]
patDurs dts = reverse $ snd $ foldl (\(counter, res) a -> (a + counter, counter:res)) (0, []) dts

genArp1 :: Arp1Fun -> Sig -> Sam -> Sam
genArp1 arpFun dt = genLoop $ \bpm d asig -> 
	sched (arpInstr asig) $ withDur d $ arpFun $ metroS bpm dt

-- | Plays ascending arpeggio of samples.
arpUp1 :: Chord -> Sig -> Sam -> Sam
arpUp1 = genArp1 . cycleE

-- | Plays descending arpeggio of samples.
arpDown1 :: Chord -> Sig -> Sam -> Sam
arpDown1 ch = arpUp1 (reverse ch)

-- | Plays arpeggio of samles with random notes from the chord.
arpOneOf1 :: Chord -> Sig -> Sam -> Sam
arpOneOf1 = genArp1 . oneOf

-- | Plays arpeggio of samles with random notes from the chord.
-- We can assign the frequencies of the notes.
arpFreqOf1 :: [D] -> Chord -> Sig -> Sam -> Sam
arpFreqOf1 freqs ch = genArp1 (freqOf (zip freqs ch))

genArp :: Arp1Fun -> [D] -> Sam -> Sam
genArp arpFun dts = genLoop $ \bpm d asig -> sched (arpInstr asig) $ fmap (notes bpm d) $ arpFun $ metroS bpm (sig $ sum dts)
	where notes bpm d pchScale = har $ fmap (\t -> singleEvent (toSec bpm t) d pchScale) $ patDurs dts		

-- | Plays ascending arpeggio of samples.
arpUp :: Chord -> [D] -> Sam -> Sam
arpUp = genArp . cycleE

-- | Plays descending arpeggio of samples.
arpDown :: Chord -> [D] -> Sam -> Sam
arpDown ch = arpUp (reverse ch)

-- | Plays arpeggio of samles with random notes from the chord.
arpOneOf :: Chord -> [D] -> Sam -> Sam 
arpOneOf = genArp . oneOf

-- | Plays arpeggio of samles with random notes from the chord.
-- We can assign the frequencies of the notes.
arpFreqOf :: [D] -> Chord -> [D] -> Sam -> Sam
arpFreqOf freqs ch = genArp (freqOf $ zip freqs ch)

metroS :: Bpm -> Sig -> Evt Unit
metroS bpm dt = metroE (recip $ toSecSig bpm dt)

-- | The pattern is influenced by the Brian Eno's work "Music fo Airports".
-- The argument is list of tripples:
--
-- > (delayTime, repeatPeriod, pitch)
-- 
-- It takes a Sample and plays it in the loop with given initial delay time.
-- The third cell in the tuple pitch is a value for scaling of the pitch in tones.
forAirports :: [(D, D, D)] -> Sam -> Sam
forAirports xs sample = mean $ flip fmap xs $ 
    \(delTime, loopTime, note) -> del delTime $ pat [loopTime] (atPch (sig note) sample)

-- | The pattern is influenced by the Brian Eno's work "Music fo Airports".
-- It's more generic than pattern @forAirport@
-- The argument is list of tripples:
--
-- > (delayTime, repeatPeriod, Sample)
-- 
-- It takes a list of Samples and plays them in the loop with given initial delay time and repeat period.
genForAirports :: [(D, D, Sam)] -> Sam
genForAirports xs = mean $ fmap (\(delTime, loopTime, sample) -> del delTime $ pat [loopTime] sample) xs



arp1 :: (SigSpace a, Sigs a) => (D -> SE a) -> D -> D -> Int -> [D] -> a
arp1 instr bpm dt n ch = sched (\(amp, cps) -> fmap (mul (sig amp)) $ instr cps) $ 
	withDur (toSec bpm dt) $ cycleE (lcmList (1 : replicate (n - 1) 0.7) ch) $ metroS bpm (sig dt)

-- | The arpeggiator for the sequence of chords. 
--
-- > arpy instrument chordPeriod speedOfTheNote accentNumber chords 
--
-- The first argument is an instrument that takes in a frequency of
-- the note in Hz. The second argument is the period of
-- chord change (in beats). The next argument is the speed 
-- of the single note (in beats). The integer argument
-- is number of notes in the group. Every n'th note is louder.
-- The last argument is the sequence of chords. The chord is
-- the list of frequencies.
arpy :: (D -> SE Sig2) -> D -> D -> Int -> [[D]] -> Sam
arpy instr chordPeriod speed accentNum chords = Sam $ do
	bpm <- ask
	res <- unSam $ loop $ flow $ map (linEnv 0.05 0.05 . fromSig2 chordPeriod . arp1 instr bpm speed accentNum) chords
	return $ S (samSig res) InfDur

-- | Applies random panning to every sample playback.
atPanRnd :: Sam -> Sam
atPanRnd = bindSam rndPan2

-- | Applies random amplitude scaling with gauss distribution with given radius (centered at 1).
atVolGauss :: D -> Sam -> Sam
atVolGauss k = bindSam (gaussVol k)

-- | Applies random amplitude scaling to every sample playback.
atVolRnd :: (D, D) -> Sam -> Sam
atVolRnd k = bindSam (rndVol k)

class ToSam a where
	toSam :: a -> Sam

limSam :: ToSam a => D -> a -> Sam
limSam dt = lim dt . toSam

instance ToSam Sig where
	toSam x = Sam $ return $ S (x, x) InfDur

instance ToSam Sig2 where
	toSam x = Sam $ return $ S x InfDur

instance ToSam (SE Sig) where
	toSam x = Sam $ do
		y <- lift x
		return $ S (y, y) InfDur

instance ToSam (SE Sig2) where
	toSam x = Sam $ do
		y <- lift x
		return $ S y InfDur

---------------------------------------------------------------
--- reading from RAM


-- | It's the same as loopRam but wrapped in Sam (see "Csound.Air.Wav").
ramLoop :: Fidelity -> TempoSig -> PitchSig -> String -> Sam
ramLoop winSize tempo pitch file = toSam $ loopRam winSize tempo pitch file

-- | It's the same as readRam but wrapped in Sam (see "Csound.Air.Wav").
ramRead :: Fidelity -> TempoSig -> PitchSig -> String -> Sam
ramRead winSize tempo pitch file = sig2 (lengthSnd file / ir tempo) $ readRam winSize tempo pitch file

-- | It's the same as loopSeg but wrapped in Sam (see "Csound.Air.Wav").
segLoop :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
segLoop winSize ds tempo pitch file = toSam $ loopSeg winSize ds tempo pitch file

-- | It's the same as readSeg but wrapped in Sam (see "Csound.Air.Wav").
segRead :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
segRead winSize ds@(kmin, kmax) tempo pitch file = sig2 (ir $ (kmax - kmin) / tempo) $ readSeg winSize ds tempo pitch file

-- | It's the same as loopRel but wrapped in Sam (see "Csound.Air.Wav").
relLoop :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
relLoop winSize ds tempo pitch file = toSam $ loopRel winSize ds tempo pitch file

-- | It's the same as readRel but wrapped in Sam (see "Csound.Air.Wav").
relRead :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
relRead winSize ds@(kmin, kmax) tempo pitch file = sig2 (ir $ (kmax - kmin) / tempo) $ readRel winSize ds tempo pitch file

-- | It's the same as loopRam1 but wrapped in Sam (see "Csound.Air.Wav").
ramLoop1 :: Fidelity -> TempoSig -> PitchSig -> String -> Sam
ramLoop1 winSize tempo pitch file = toSam $ loopRam1 winSize tempo pitch file

-- | It's the same as readRam1 but wrapped in Sam (see "Csound.Air.Wav").
ramRead1 :: Fidelity -> TempoSig -> PitchSig -> String -> Sam
ramRead1 winSize tempo pitch file = sig1 (lengthSnd file / ir tempo) $ readRam1 winSize tempo pitch file

-- | It's the same as loopSeg1 but wrapped in Sam (see "Csound.Air.Wav").
segLoop1 :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
segLoop1 winSize ds tempo pitch file = toSam $ loopSeg1 winSize ds tempo pitch file

-- | It's the same as readSeg1 but wrapped in Sam (see "Csound.Air.Wav").
segRead1 :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
segRead1 winSize ds@(kmin, kmax) tempo pitch file = sig1 (ir $ (kmax - kmin) / tempo) $ readSeg1 winSize ds tempo pitch file

-- | It's the same as loopRel1 but wrapped in Sam (see "Csound.Air.Wav").
relLoop1 :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
relLoop1 winSize ds tempo pitch file = toSam $ loopRel1 winSize ds tempo pitch file

-- | It's the same as readRel1 but wrapped in Sam (see "Csound.Air.Wav").
relRead1 :: Fidelity -> (Sig, Sig) -> TempoSig -> PitchSig -> String -> Sam
relRead1 winSize ds@(kmin, kmax) tempo pitch file = sig1 (ir $ (kmax - kmin) / tempo) $ readRel1 winSize ds tempo pitch file
