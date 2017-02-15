import std.conv: to;
import core.stdc.stdio;
import core.stdc.ctype;
import std.stdio: write, writeln, writefln;

//===--------------------------------------------------------===//
// Lexer
//===--------------------------------------------------------===//

/// The lexer returns tokens [0-255] if it is an unknown character,
/// otherwise one of these for known things.

enum Token {
    tok_eof = -1,

    // commands
    tok_def = -2,
    tok_extern = -3,

    // primary
    tok_identifier = -4,
    tok_number = -5,
};

static char[] IdentifierStr;
static double NumVal;
static int CurTok;
static int getNextToken() {
    CurTok = gettok();
    printStatus();
    return CurTok;
}

void printStatus() {
    string token;
    with (Token) switch (CurTok) {
        case tok_eof:
            token = "EOF";
            break;
        case tok_def:
            token = "DEF";
            break;
        case tok_extern:
            token = "EXTERN";
            break;
        case tok_identifier:
            token = "IDENT";
            writefln("\t\t\t\tTOKEN{%s,%s}", token, IdentifierStr);
            break;
        case tok_number:
            token = "NUM";
            writefln("\t\t\t\tTOKEN{%s,%f}", token, NumVal);
            break;
        default:
            token = (cast(char)CurTok).to!string();
            writefln("\t\t\t\tTOKEN{%s}", token);
            break;
    }
}

char nextChar() {
    char c = cast(char)getchar();
    writeln("->", c);
    return c;
}

char LastChar = ' ';
/// gettok - Returns the next token from standard input.
int gettok() {
    while (isspace(LastChar))
        LastChar = nextChar();

    if (isalpha(LastChar)) { // identifier: [a-zA-Z][a-zA-Z0-9]*
        IdentifierStr = [LastChar];
        while (isalnum((LastChar = nextChar())))
            IdentifierStr ~= LastChar;

        if (IdentifierStr == "def") {
            return Token.tok_def;
        }
        if (IdentifierStr == "extern") {
            return Token.tok_extern;
        }
        return Token.tok_identifier;
    }

    if (isdigit(LastChar) || LastChar == '.') { // Number: [0-9.]+
        char[] NumStr;
        do {
            NumStr ~= LastChar;

            LastChar = nextChar();
        } while (isdigit(LastChar) || LastChar == '.');

        NumVal = to!double(NumStr);
        return Token.tok_number;
    }

    if (LastChar == '#' ) {
        // Comment until end of line.
        do
            LastChar = nextChar();
        while (LastChar != EOF && LastChar != '\n' && LastChar != '\r');

        if (LastChar != EOF) {
            return gettok();
        }
    }

    // check end of file. Don't eat the EOF.
    if (LastChar == EOF) {
        return Token.tok_eof;
    }

    // Otherwise, just return the character as its ascii value.
    char ThisChar = LastChar;
    LastChar = nextChar();
    return ThisChar;
}


//===------------------------------===//
// Parser
//===------------------------------===//

/// ExprAST - Base class for all expression nodes.
class ExprAST {
};

/// NumberExprAST - Expression class for numeric literals like "1.0".
class NumberExprAST : ExprAST {
    double Val;

public:
    this(double val) {
        Val = val;
    }

    override string toString() {
        import std.conv: to;
        return "Num(" ~ Val.to!string ~ ")";
    }
}

/// VariableExprAST - Expression class for referencing a variable, like "a".
class VariableExprAST : ExprAST {
    string Name;

public:
    this(const ref string name) {
        Name = name;
    }
}

/// BinaryExprAST - Expression class for a binary operator.
class BinaryExprAST : ExprAST {
    char Op;
    ExprAST LHS, RHS; // TODO: C++: std::unique_ptr<ExprAST>, should we use uniq_ptr?

public:
    this(char op, ExprAST lhs, ExprAST rhs) {
        op = op;
        lhs = lhs;
        rhs = rhs;
    }

}

/// CallExprAST - Expression class for function calls.
class CallExprAST : ExprAST {
    string Callee;
    ExprAST[] Args;

public:
    this(const ref string callee, ExprAST[] args) {
        Callee = callee;
        Args = args;
    }
}

/// PrototypeAST - This class represents the "prototype" for a function
/// which captures its name, and its argument names (thus implicitly the number
/// of arguments the function takes).
class PrototypeAST {
    string Name;
    string[] Args;
public:
    this(const ref string name, string[] args) {
        Name = name;
        Args = args;
    }

    ref string getName() { return Name; } // TODO: return value not const here
}

/// FunctionAST - This class represents a function definition itself.
class FunctionAST {
    PrototypeAST Proto;
    ExprAST Body;

public:
    this(PrototypeAST proto, ExprAST _body) {
        Proto = proto;
        Body = _body;
    }

}

ExprAST LogError(const char* str) {
    fprintf(stderr, "LogError: %s\n", str);
    return null;
}

PrototypeAST LogErrorP(const char* str) {
    LogError(str);
    return null;
}

/// numberexpr ::= number
ExprAST ParseNumberExpr() {
    getNextToken();
    auto n = new NumberExprAST(NumVal);
    return n;
}

/// parenexpr ::= '(' expression ')'
ExprAST ParseParenExpr() {
    getNextToken(); // eat (.
    auto V = ParseExpression();
    if (!V) return null;
    if (CurTok != ')')
        return LogError("expected ')'");
    writeln("EATS )");
    getNextToken(); // eat ).
    return V;
}

/// identifierexpr
///    ::= identifier
///    ::= identifier '(' expression* ')'
ExprAST ParseIdentifierExpr() {
    import std.conv: to;
    string IdName = IdentifierStr.to!string;

    getNextToken(); // eat identifier.

    if (CurTok != '(') // Simple varialbe reference.
        return new VariableExprAST(IdName);

    writeln("A function call");
    // Call.
    getNextToken(); // eat (.
    ExprAST[] Args;
    if (CurTok != ')') {
        while (true) {
            if (auto Arg = ParseExpression())
                Args ~= Arg;
            else
                return null;

            if (CurTok == ')')
                break;

            if (CurTok != ',')
                return LogError("Expected ')' or ',' in argument list");
            getNextToken(); // eats ','.
        }
    }

    getNextToken(); // eat ).

    return new CallExprAST(IdName, Args);
}

/// Primary
///     ::= identifier
///     ::= numberexpr
///     ::= parenexpr
ExprAST ParsePrimary() {
    with(Token) switch (CurTok) {
    default:
        return LogError("unknown token when expecting an expression");
    case tok_identifier:
        return ParseIdentifierExpr();
    case tok_number:
        return ParseNumberExpr();
    case '(':
        writeln("(parse paren)");
        return ParseParenExpr();
    }
}

int[char] BinopPrecedence;

int GetTokPrecedence() {
    import std.ascii;
    char t = cast(char)CurTok;
    
    if (!(t == '+' || t == '-' || t == '*' || t == '/')) {
        return -1;
    }

    writeln("Prec[", t, "]");
    // Make sure it's a declared binop.
    int TokPrec = BinopPrecedence[t];
    if (TokPrec <= 0) return -1;
    return TokPrec;
}

/// expression
///     ::= primary binoprhs
///
ExprAST ParseExpression() {
    auto LHS = ParsePrimary();
    writeln("Got LHS:", LHS);
    if (!LHS)
        return null;
    return ParseBinOpRHS(0, LHS);
}

/// binoprhs
///     ::= ('+' primary)*
ExprAST ParseBinOpRHS(int ExprPrec, ExprAST LHS) {
    writeln("[ParseBinOpRHS]");

    // If this is a binop, find its precedence.
    while (true) {
        int TokPrec = GetTokPrecedence();

        // If this is a binop that binds at least as tightly as the current binop,
        // consume it, otherwise we are done.
        if (TokPrec < ExprPrec) {
            return LHS;
        }

        int BinOp = CurTok;
        getNextToken(); // eat binop.

        // parse the primary expression after the binary operator.
        writeln("parse RHS");
        printStatus();
        auto RHS = ParsePrimary();
        if (RHS) writeln("Got RHS:", RHS);
        if (!RHS)
            return null;

        // If BinOp binds less tightly with RHS than the operator after RHS, let
        // the pending operator take RHS as its LHS.
        /*
        int NextPrec = GetTokPrecedence();
        if (TokPrec < NextPrec) {
            RHS = ParseBinOpRHS(TokPrec + 1, RHS);
            if (!RHS)
                return null;
        }
        */

        // Merge LHS/RHS
        LHS = new BinaryExprAST(cast(char)BinOp, LHS, RHS);
    }
}

/// prototype
///     ::= id '(' id* ')'
PrototypeAST ParsePrototype() {
    printStatus();
    if (CurTok != Token.tok_identifier) {
        return LogErrorP("Expected function name in prototype:");
    }

    import std.conv: to;
    string FnName = IdentifierStr.to!string;
    getNextToken();
    printStatus();

    if (CurTok != '(') {
        return LogErrorP("Expected '(' in prototype");
    }

    string[] ArgNames;
    while (getNextToken() == Token.tok_identifier)
        ArgNames ~= IdentifierStr.to!string;
    if (CurTok != ')')
        return LogErrorP("Expected ')' in prototype");

    // success.
    getNextToken(); // eat ')'.

    return new PrototypeAST(FnName, ArgNames);
}

/// definition ::= 'def' prototype expression
FunctionAST ParseDefinition() {
    getNextToken(); // eat def.
    auto Proto = ParsePrototype();
    if (!Proto)
        return null;

    if (auto E = ParseExpression())
        return new FunctionAST(Proto, E);
    return null;
}

/// toplevelexpr ::= expression
FunctionAST ParseTopLevelExpr() {
    if (auto E = ParseExpression()) {
        writeln("Got An Expression");
        // Make an anonymous proto.
        string[] Args;
        string FnName = "__anon_expr";
        auto Proto = new PrototypeAST(FnName, Args);
        return new FunctionAST(Proto, E);
    }
    return null;
}

/// external ::= 'extern' prototype
PrototypeAST ParseExtern() {
    getNextToken(); // eat extern.
    return ParsePrototype();
}

//===----------------------------------===//
// Top-Level parsing
//===----------------------------------===//
void HandleDefinition() {
    if (ParseDefinition()) {
        fprintf(stderr, "Parsed a function definition.\n");
    } else {
        getNextToken();
    }
}

void HandleExtern() {
    if (ParseExtern()) {
        fprintf(stderr, "Parsed an extern\n");
    } else {
        getNextToken();
    }
}

void HandleTopLevelExpression() {
    // Evaluate a top-level expression into an anonymous function.
    if (ParseTopLevelExpr()) {
        fprintf(stderr, "Parsed a top-level expr\n");
    } else {
        getNextToken();
    }
}

/// top ::= definition | external | expression | ';'
void MainLoop() {
    while (true) {
        write("ready> ");
        with(Token) switch (CurTok) {
            case tok_eof:
                return;
            case ';': // ignore top level semicolons
                getNextToken();
                break;
            case tok_def:
                HandleDefinition();
                break;
            case tok_extern:
                HandleExtern();
                break;
            default:
                HandleTopLevelExpression();
                break;
        }
    }
}

//===----------------------------------------===//
// main driver code.
//===----------------------------------------===//
void main()
{
    // Install standard binary operators.
    // 1 is lowest precedence.
    BinopPrecedence['<'] = 10;
    BinopPrecedence['+'] = 20;
    BinopPrecedence['-'] = 20;
    BinopPrecedence['*'] = 40;

    /*
    while (true) {
        fprintf(stderr, "ready> ");
        getNextToken();
    }
    */

    // Prime the first token.
    fprintf(stderr, "ready> ");
    getNextToken();
    // Run the main "interpreter loop" now.
    MainLoop();
}
