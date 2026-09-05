const fs = require('fs');
if(!fs.existsSync('num.txt')) {
    fs.writeFileSync('num.txt', '0');
}else{
    let num = parseInt(fs.readFileSync('num.txt', 'utf-8'));
    num++;
    fs.writeFileSync('num.txt', num.toString());
}
