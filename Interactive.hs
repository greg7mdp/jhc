module Interactive(Interactive.interact) where

import Control.Monad.Reader
import Control.Monad.Identity
import Control.Monad.Writer
import Control.Monad.Trans
import Data.Monoid
import IO(stdout,ioeGetErrorString)
import List(sort)
import Maybe
import Monad
import qualified Data.Map as Map
import qualified Text.PrettyPrint.HughesPJ as P
import Text.Regex
import Text.Regex.Posix(regcomp,regExtended)


import DataConstructors
import Doc.DocLike
import Doc.PPrint
import Doc.Pretty
import FrontEnd.HsParser(parseHsStmt)
import FrontEnd.KindInfer
import FrontEnd.ParseMonad
import FrontEnd.Rename
import FrontEnd.SrcLoc
import FrontEnd.Tc.Main
import FrontEnd.Tc.Monad
import FrontEnd.Tc.Type
import FrontEnd.Desugar(desugarHsStmt)
import GenUtil
import Class
import Ho
import HsPretty()
import HsSyn
import Name.Name
import Options
import qualified FrontEnd.Infix
import qualified HsPretty
import qualified Text.PrettyPrint.HughesPJ as PP
import Representation hiding(flattenType)
import TIMain(tiProgram)
import Type(schemeToType)
import TypeSynonyms(showSynonym)
import TypeSyns
import TypeSigs
import Util.Interact
import Warning

printDoc doc = do
    displayIO stdout (renderPretty 0.9 80 doc)
    putStrLn ""

grep_opts = [
 "f - match normal value",
 "C - match data constructor",
 "T - match type constructor",
 "L - match class"
 ]

nameTag :: NameType -> Char
nameTag TypeConstructor = 'T'
nameTag DataConstructor = 'C'
nameTag ClassName = 'L'
nameTag Val = 'f'
nameTag _ = '?'

data InteractiveState = IS {
    stateHo :: Ho,
    stateInteract :: Interact,
    stateModule :: Module,
    stateImports :: [(Name,[Name])],
    stateOptions :: Opt
    }

isInitial = IS {
    stateHo = mempty,
    stateInteract = emptyInteract,
    stateModule = Module "Main",
    stateImports = [],
    stateOptions = options
    }


newtype In a = MkIn (ReaderT InteractiveState IO a)
    deriving(MonadIO,Monad,Functor,MonadReader InteractiveState)

runIn :: InteractiveState -> In a -> IO a
runIn is (MkIn x) = runReaderT x is

instance OptionMonad In where
    getOptions = asks stateOptions

instance MonadWarn In where
    addWarning x = liftIO $ addWarning x



interact :: Ho -> IO ()
interact ho = mre where
    mre = case optStmts options of
        [] -> go
        xs -> runInteractions initialInteract (concatMap lines $ reverse xs) >> exitSuccess
    go = do
        putStrLn "--------------------------------------------------------------"
        putStrLn "Welcome to the jhc interactive experience. use :help for help."
        putStrLn versionString
        putStrLn "--------------------------------------------------------------"
        runInteraction initialInteract ":execfile jhci.rc"
        beginInteraction initialInteract
    initialInteract = emptyInteract {
        interactSettables = ["prog", "args"],
        interactVersion = versionString,
        interactCommands = commands,
        interactWords = map (show . fst ) $ stateImports isStart,
        interactHistFile = Just ".jhci-hist",
        interactComment = Just "--",
        interactExpr = do_expr
        }
    dataTable = hoDataTable ho
    commands = [cmd_mods,cmd_grep]
    cmd_mods = InteractCommand { commandName = ":mods", commandHelp = "mods currently loaded modules", commandAction = do_mods }
    do_mods act _ _ = do
        printDoc $ fillSep (map tshow $ Map.keys $  hoExports ho)
        return act
    cmd_grep = InteractCommand { commandName = ":grep", commandHelp = "show names matching a regex", commandAction = do_grep }
    do_grep act _ "" = do
        putStrLn ":grep [options] <regex>"
        putStrLn "Valid options:"
        putStr $ unlines grep_opts
        return act
    do_grep act _ arg = do
        let (opt,reg) = case simpleUnquote arg of
                [x] -> ("TCLf",x)
                xs -> f "" xs where
            f opt [x] = (opt,x)
            f opt ~(x:xs) = f (x ++ opt) xs
            f _ _ = undefined
        rx <- catch ( Just `fmap` regcomp reg regExtended) (\_ -> return Nothing)
        case rx of
            Nothing -> putStrLn $ "Invalid regex: " ++ arg
            --Just rx -> mapM_ putStrLn $ sort [ nameTag (nameType v):' ':show v <+> "::" <+> ptype v  | v <- Map.keys (hoDefs ho), isJust (matchRegex rx (show v)), nameTag (nameType v) `elem` opt ]
            Just rx -> mapM_ putStrLn $ sort [ pshow opt v  | v <- Map.keys (hoDefs ho), isJust (matchRegex rx (show v)), nameTag (nameType v) `elem` opt ]
        return act
    ptype x | Just r <- pprintTypeOfCons dataTable x = r
    ptype k | Just r <- Map.lookup k (hoAssumps ho) = show (pprint r:: PP.Doc)
    ptype x | nameType x == ClassName = hsep (map kindShow $ kindOfClass x (hoKinds ho))
    ptype x = "UNKNOWN: " ++ show (nameType x,x)
    isStart =  isInitial { stateHo = ho, stateImports = runIdentity $ calcImports ho False (Module "Prelude") }
    do_expr :: Interact -> String -> IO Interact
    do_expr act s = case parseStmt (s ++ "\n") of
        Left m -> putStrLn m >> return act
        Right e -> do
            catch (runIn isStart { stateInteract = act } $ executeStatement e) $ (\e -> putStrLn $ ioeGetErrorString e)
            return act
    pshow _opt v
        | Just d <- showSynonym (show . (pprint :: HsType -> PP.Doc) ) v (hoTypeSynonyms ho) = nameTag (nameType v):' ':d
        | otherwise = nameTag (nameType v):' ':show v <+> "::" <+> ptype v

kindShow Star = "*"
kindShow x = parens (pprint x)

parseStmt ::  Monad m => String -> m HsStmt
parseStmt s = case runParserWithMode ParseMode { parseFilename = "(jhci)" } parseHsStmt  s  of
                      ParseOk _ e -> return e
                      ParseFailed sl err -> fail $ show sl ++ ": " ++ err

printStatement stmt = do
        liftIO $ putStrLn $ HsPretty.render $ HsPretty.ppHsStmt $  stmt

procErrors :: In a -> In ()
procErrors act = do
    b <- liftIO $ printIOErrors
    if b then return () else act >> return ()


executeStatement :: HsStmt -> In ()
executeStatement stmt = do
    is@IS { stateHo = ho } <- ask
    stmt <- desugarHsStmt stmt
    stmt' <- renameStatement mempty (stateImports is) (stateModule is) stmt
    procErrors $ do
    --printStatement stmt'
    stmt'' <- expandTypeSynsStmt (hoTypeSynonyms ho) (stateModule is) stmt'
    stmt''' <- FrontEnd.Infix.infixStatement (hoFixities ho) stmt''
    procErrors $ do
    printStatement stmt'''
    tcStatement stmt'''

tcStatement :: HsStmt -> In ()
tcStatement HsLetStmt {} = liftIO $ putStrLn "let statements not yet supported"
tcStatement HsGenerator {} = liftIO $ putStrLn "generators not yet supported"
tcStatement (HsQualifier e) = do
    tcStatementTc (HsQualifier e)
    when False $ do
    is@IS { stateHo = ho } <- ask
    let importVarEnv = Map.fromList [ (x,y) | (x,y) <- Map.toList $ hoAssumps ho, nameType x == Val ]
        importDConsEnv = Map.fromList [ (x,y) | (x,y) <- Map.toList $ hoAssumps ho, nameType x ==  DataConstructor ]
        ansName = Qual (stateModule is) (HsIdent "ans")
        ansName' = toName Val ansName
    opt <- getOptions
    localVarEnv <- liftIO $ tiProgram
                opt                            -- options
                (stateModule is)               -- name of the module
                mempty                         -- environment of type signatures
                (hoKinds ho)                   -- kind information about classes and type constructors
                (hoClassHierarchy ho)          -- class hierarchy with instances
                importDConsEnv                 -- data constructor type environment
                importVarEnv                   -- type environment
                [([],[HsPatBind bogusASrcLoc (HsPVar ansName) (HsUnGuardedRhs e) []])]                        -- binding groups
    procErrors $ do
    vv <- Map.lookup ansName' localVarEnv
    liftIO $ putStrLn $ show (text "::" <+> pprint vv :: P.Doc)


tcStatementTc :: HsStmt -> In ()
tcStatementTc HsLetStmt {} = liftIO $ putStrLn "let statements not yet supported"
tcStatementTc HsGenerator {} = liftIO $ putStrLn "generators not yet supported"
tcStatementTc (HsQualifier e) = do
    is@IS { stateHo = ho } <- ask
    let tcInfo = tcInfoEmpty {
        tcInfoEnv = Map.map schemeToType (hoAssumps ho),
        tcInfoSigEnv = Map.map schemeToType $ collectSigEnv (hoKinds ho) (HsQualifier e),
        tcInfoModName =  show (stateModule is),
        tcInfoKindInfo = (hoKinds ho),
        tcInfoClassHierarchy = (hoClassHierarchy ho)

        }
    runTc tcInfo $ do
    box <- newBox Star
    (_,ps') <- listen $ tiExpr e box
    ps' <- flattenType ps'
    let ps = Class.simplify (hoClassHierarchy ho) ps'
    (ps :=> vv) <- flattenType (ps :=> box)
    TForAll vs ([] :=> t) <- generalize vv -- quantify (tv vv) qt
    --liftIO $ putStrLn $ show (text "::" <+> pprint vv' :: P.Doc)
    liftIO $ putStrLn $   "::" <+> prettyPrintType (TForAll vs (ps :=> t))
    ce <- getCollectedEnv
    liftIO $ mapM_ putStrLn [ pprint n <+>  "::" <+> prettyPrintType s |  (n,s) <- Map.toList ce]


calcImports :: Monad m => Ho -> Bool -> Module -> m [(Name,[Name])]
calcImports ho qual mod = case Map.lookup mod (hoExports ho) of
    Nothing -> fail $ "calcImports: module not known " ++ show mod
    Just es -> do
        let ls = sortGroupUnderFG fst snd
                [ (n,if qual then [setModule mod n] else [setModule mod n,toUnqualified n]) | n <- es]
            ls' = concat [ zip (concat nns) (repeat [n]) | (n,nns) <- ls ]
        return $ Map.toList $ Map.map snub $ Map.fromListWith (++) ls'

