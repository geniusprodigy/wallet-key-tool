package prof7bit.bitcoin.wallettool

import com.google.bitcoin.core.ECKey
import com.google.bitcoin.core.NetworkParameters
import java.io.File
import java.math.BigInteger
import java.util.ArrayList
import java.util.Date
import java.util.Iterator
import java.util.List
import org.slf4j.LoggerFactory
import prof7bit.bitcoin.wallettool.fileformats.BlockchainInfoStrategy
import prof7bit.bitcoin.wallettool.fileformats.WalletDumpStrategy
import prof7bit.bitcoin.wallettool.fileformats.MultibitStrategy

class WalletKeyTool implements Iterable<KeyObject> {
    val log = LoggerFactory.getLogger(this.class)
    @Property var (String)=>String promptFunc = []
    @Property var (String)=>boolean YesNoFunc = []
    @Property var (String)=>void alertFunc = []
    @Property var (Object)=>void notifyChangeFunc = []
    @Property var (int,String)=>void reportProgressFunc = [p, s|]
    @Property var NetworkParameters params = null
    private var List<KeyObject> keys = new ArrayList

    var ImportExportStrategy importExportStrategy

    def prompt(String msg){
        promptFunc.apply(msg)
    }

    def alert(String msg){
        alertFunc.apply(msg)
    }

    def confirm(String msg){
        yesNoFunc.apply(msg)
    }

    def notifyChange(){
        notifyChangeFunc.apply(null)
    }

    def reportProgress(int percent, String status){
        reportProgressFunc.apply(percent, status)
    }

    def void setImportExportStrategy(Class<? extends ImportExportStrategy> strat) throws InstantiationException, IllegalAccessException {
        importExportStrategy = strat.newInstance
        importExportStrategy.walletKeyTool = this
    }

    def load(File file, String pass) throws Exception {
        val strategies = #[
            WalletDumpStrategy,
            MultibitStrategy,
            BlockchainInfoStrategy
        ]

        for (strat : strategies){
            if (tryLoadWithStrategy(file, null, strat)){
                notifyChange
                return
            }
        }

        var password = pass
        if (password == null){
            password = prompt("none of the unencrypted strategies succeeded,\nwe might need a password")
        }
        if (password == null || password.length == 0){
            throw new Exception("import canceled")
        }

        for (strat : strategies){
            if (tryLoadWithStrategy(file, password, strat)){
                notifyChange
                return
            }
        }
        throw new Exception("import failed, none of the strategies worked. See log level TRACE for details")
    }

    def tryLoadWithStrategy(File file, String pass, Class<? extends ImportExportStrategy> strat)throws InstantiationException, IllegalAccessException {
        setImportExportStrategy(strat)
        if (pass == null){
            log.info("trying import strategy " + strat.simpleName)
        }else{
            log.info("trying encrypted import strategy " + strat.simpleName)
        }
        try {
            importExportStrategy.load(file, pass)
            log.info(strat.simpleName + " succeeded!")
            return true
        } catch (Exception e) {
            log.info(strat.simpleName + " said: " + e.message)
            log.trace("attempt to use " + strat.simpleName + " failed", e)
            return false
        }
    }

    def save(File file, String pass, Class<? extends ImportExportStrategy> strat) throws Exception {
        setImportExportStrategy(strat)
        importExportStrategy.save(file, pass)
    }

    def add(KeyObject key){
        var skip = false
        var KeyObject duplicate = null
        for (existingKey : keys){
            if (existingKey.addrStr.equals(key.addrStr)){
                if (!existingKey.hasPrivKey && key.hasPrivKey){
                    log.info("replace watch-only {} with private key", existingKey.addrStr)
                    duplicate = existingKey
                } else {
                    log.info("skip existing {}", existingKey.addrStr)
                    skip = true
                }
            }
        }
        if (duplicate != null){
            keys.remove(duplicate)
        }
        if (!skip){
            if (params == null){
                params = key.params
                log.debug("initialized params of WalletKeyTool with params of first added key")
            }
            if (params.equals(key.params)){
                keys.add(key)
                notifyChange
            }else{
                log.error("{} is from a different network. Cannot mix them in the same wallet",
                    key.addrStr
                )
            }
            return key
        } else {
            return null
        }
    }

    def add(ECKey ecKey){
        // KeyWrapper constructor will know what to do if params==null
        val k = new KeyObject(ecKey, params)
        return add(k)
    }

    def addKeyFromOtherInstance(WalletKeyTool other, int i){
        val key = other.get(i)
        keys.add(key)
        notifyChange
    }

    def remove(int i){
        keys.remove(i)
        notifyChange
    }

    def clear(){
        keys.clear
        params = null
        notifyChange
    }

    def addOtherCompressedVersion(int i){
        val KeyObject ko_this = get(i)
        var ECKey ec_other
        var String label
        if (ko_this.compressed) {
            ec_other = new ECKey(new BigInteger(1, ko_this.ecKey.privKeyBytes), null, false)
            label = "uncompressed version of "
        } else {
            ec_other = new ECKey(new BigInteger(1, ko_this.ecKey.privKeyBytes), null, true)
            label = "compressed version of "
        }
        val ko_other = new KeyObject(ec_other, params)
        ko_other.label = label + ko_this.addrStr + " " + ko_this.label
        return add(ko_other)
    }

    def getKeyCount() {
        keys.length
    }

    def get(int i) {
        keys.get(i)
    }

    def getAddressStr(int i) {
        get(i).addrStr
    }

    def getPrivkeyStr(int i) {
        get(i).privKeyStr
    }

    def getCreationTimeSeconds(int i) {
        get(i).creationTimeSeconds
    }

    def getBalance(int i){
        get(i).balance
    }

    def getLabel(int i){
        get(i).label
    }

    def setCreationTimeSeconds(int i, long time) {
        get(i).creationTimeSeconds = time
        notifyChange
    }

    def setBalance(int i, long balance){
        get(i).balance = balance
    }

    def setLabel(int i, String label){
        get(i).label = label
    }

    def dumpToConsole() {
        for (i : 0 ..< keyCount) {
            println(getAddressStr(i) + " " + getPrivkeyStr(i) + " " + getLabel(i))
        }
    }

    def doRemoteFetchCreationDate(int i){
        val d = RemoteAddressInfo.getFirstSeen(getAddressStr(i))
        if (d > 0){
            get(i).creationTimeSeconds = d
            notifyChange
        } else {
            //  0 means not yet seen, set time to today
            // -1 means error, don't do anything
            if (d == 0){
                get(i).creationTimeSeconds = new Date().time / 1000L
                notifyChange
            }
        }
    }

    def doRemoteFetchBalance(int i){
        val b = RemoteAddressInfo.getBalance(getAddressStr(i))
        if (b > -1) {
            setBalance(i, b)
            notifyChange
        }
    }

    override iterator() {
        return new WalletKeyToolIterator(this)
    }
}

class WalletKeyToolIterator implements Iterator<KeyObject> {
    var index = 0
    var WalletKeyTool wkt

    new(WalletKeyTool wkt){
        this.wkt = wkt
    }

    override hasNext() {
        index < wkt.keyCount
    }

    override next() {
        index = index + 1
        return wkt.get(index - 1)
    }

    override remove() {
        wkt.remove(index)
    }
}
