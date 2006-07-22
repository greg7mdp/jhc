-- | All hardcoded names in the compiler should go in here
-- the convention is
-- v_foo for values
-- tc_foo for type constructors
-- dc_foo for data constructors
-- s_foo for sort names
-- rt_foo for raw names
-- class_foo for classes

module Name.Names(module Name.Names,module Name.Prim) where

import Char(isDigit)

import Name.VConsts
import Name.Name
import Name.Prim

instance TypeNames Name where
    tInt = tc_Int
    tBool = tc_Bool
    tInteger = tc_Integer
    tChar = tc_Char
    tStar = s_Star
    tHash = s_Hash
    tUnit = tc_Unit
    tIntzh = rt_int
    tCharzh = rt_HsChar
    tIntegerzh = rt_intmax_t
    tWorld__ = rt_Worldzh

instance ConNames Name where
--    vTrue = dc_True
--    vFalse = dc_False
    vEmptyList = dc_EmptyList
    vUnit = dc_Unit
    vCons = dc_Cons


-- Tuple handling

--No tuple instance because it is easy to get the namespace wrong. use 'nameTuple'
--instance ToTuple Name where
--    toTuple n = toName DataConstructor (toTuple n :: (String,String))

nameTuple _ n | n < 2 = error "attempt to create tuple of length < 2"
nameTuple t n = toName t  $ (toTuple n:: (String,String)) -- Qual (HsIdent ("(" ++ replicate (n - 1) ',' ++ ")"))

unboxedNameTuple t n = toName t $ "(#" ++ show n ++ "#)"
fromUnboxedNameTuple n = case show n of
    '(':'#':xs | (ns@(_:_),"#)") <- span isDigit xs -> return (read ns::Int)
    _ -> fail $ "Not unboxed tuple: " ++ show n

instance FromTupname Name where
    fromTupname name | m == "Prelude" = fromTupname (nn::String) where
        (_,(m,nn)) = fromName name
    fromTupname _ = fail "not a tuple"



-- The constructors

dc_Cons = toName DataConstructor ("Prelude",":")
dc_EmptyList = toName DataConstructor ("Prelude","[]")
--dc_False = toName DataConstructor ("Prelude","False")
dc_JustIO = toName DataConstructor ("Jhc.IO", "JustIO")
dc_Rational = toName DataConstructor ("Ratio",":%")
--dc_True = toName DataConstructor ("Prelude","True")
dc_Unit = toName DataConstructor ("Prelude","()")
dc_Boolzh = toName DataConstructor ("Prelude","Bool#")

tc_Absurd = toName TypeConstructor ("Jhc@","Absurd#")
tc_Arrow = toName TypeConstructor ("Jhc@","->")
tc_IOErrorCont = toName TypeConstructor ("Jhc.IO","IOErrorCont")
tc_JumpPoint = toName TypeConstructor ("Jhc.JumpPoint","JumpPoint")
tc_IOError = toName TypeConstructor ("Prelude.IOError","IOError")

tc_IOResult = toName TypeConstructor ("Jhc.IO","IOResult")
tc_IO = toName TypeConstructor ("Jhc.IO", "IO")
tc_World__ = toName TypeConstructor ("Jhc.IO","World__")

tc_Bool = toName TypeConstructor ("Prelude","Bool")
tc_List = toName TypeConstructor ("Prelude","[]")
tc_Ptr = toName TypeConstructor ("Foreign.Ptr","Ptr")
tc_Ratio = toName TypeConstructor ("Ratio","Ratio")
tc_Unit = toName TypeConstructor  ("Prelude","()")


rt_Worldzh = toName RawType "World#"
rt_tag = toName RawType "tag#"

s_Star = toName SortName ("Jhc@","*")
s_Hash = toName SortName ("Jhc@","#")

v_error = toName Val ("Prelude","error")
v_toEnum = toName Val ("Prelude","toEnum")
v_fromEnum = toName Val ("Prelude","fromEnum")
v_minBound = toName Val ("Prelude","minBound")
v_maxBound = toName Val ("Prelude","maxBound")
v_fail = toName Val ("Prelude","fail")
v_concatMap = toName Val ("Jhc.List","concatMap")
v_map = toName Val ("Prelude","map")
v_and = toName Val ("Prelude","&&")
v_filter = toName Val ("Prelude","filter")
v_foldr = toName Val ("Jhc.List","foldr")
v_undefined = toName Val ("Prelude","undefined")
v_undefinedIOErrorCont = toName Val ("Jhc.IO","undefinedIOErrorCont")
v_silly = toName Val ("Jhc@","silly")

sFuncNames = FuncNames {
    func_bind = toName Val ("Prelude",">>="),
    func_bind_ = toName Val ("Prelude",">>"),
    func_concatMap = toName Val ("Jhc.List","concatMap"),
    func_equals = toName Val ("Prelude","=="),
    func_fromInteger = toName Val ("Prelude","fromInteger"),
    func_fromInt = toName Val ("Prelude","fromInt"),
    func_fromRational = toName Val ("Prelude","fromRational"),
    func_negate = toName Val ("Prelude","negate"),
    func_leq = toName Val ("Prelude","<="),
    func_geq = toName Val ("Prelude",">="),
    func_lt = toName Val ("Prelude","<"),
    func_gt = toName Val ("Prelude",">"),
    func_compare = toName Val ("Prelude","compare"),
    func_neq = toName Val ("Prelude","/="),
    func_fromEnum = toName Val ("Prelude","fromEnum"),
    func_toEnum = toName Val ("Prelude","toEnum"),
    func_minBound = toName Val ("Prelude","minBound"),
    func_maxBound = toName Val ("Prelude","maxBound"),
    func_enumFrom = toName Val ("Prelude","enumFrom"),
    func_enumFromThen = toName Val ("Prelude","enumFromThen"),
    func_range = toName Val ("Data.Ix","range"),
    func_index = toName Val ("Data.Ix","index"),
    func_inRange = toName Val ("Data.Ix","inRange"),
    func_runExpr = toName Val ("Jhc.IO","runExpr"),
    func_runMain = toName Val ("Jhc.IO","runMain"),
    func_runNoWrapper = toName Val ("Jhc.IO","runNoWrapper")
    }



class_Eq = toName ClassName ("Prelude","Eq")
class_Ord = toName ClassName ("Prelude","Ord")
class_Enum = toName ClassName ("Prelude","Enum")
class_Bounded = toName ClassName ("Prelude","Bounded")
class_Show = toName ClassName ("Prelude.Text","Show")
class_Read = toName ClassName ("Prelude.Text","Read")
class_Ix = toName ClassName ("Ix","Ix")
class_Functor = toName ClassName ("Prelude","Functor")
class_Monad = toName ClassName ("Prelude","Monad")
class_Num = toName ClassName ("Prelude","Num")
class_Real = toName ClassName ("Prelude","Real")
class_Integral = toName ClassName ("Prelude","Integral")
class_Fractional = toName ClassName ("Prelude","Fractional")
class_Floating = toName ClassName ("Prelude","Floating")
class_RealFrac = toName ClassName ("Prelude","RealFrac")
class_RealFloat = toName ClassName ("Prelude","RealFloat")

