import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class InvoiceService {
  static Future<void> generateAndShareInvoice({
    required String matchId,
    required double amount,
    required String venueName,
    required String date,
    required String time,
    required String companyName,
    required String cui,
    required String regCom,
    required String address,
    required String email,
  }) async {
    final pdf = pw.Document();
    
    // Add page
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PingPong Playhub SRL', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('CUI: RO12345678'),
                        pw.Text('J40/1234/2026'),
                        pw.Text('București, România'),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('FACTURĂ FISCALĂ', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                        pw.SizedBox(height: 8),
                        pw.Text('Seria: PPP Nr. ${matchId.substring(0, 6).toUpperCase()}'),
                        pw.Text('Data: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}'),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 40),
                
                // Client Info
                pw.Text('Cumpărător:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Nume Firmă / Client: $companyName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('CUI / CIF: $cui'),
                      if (regCom.isNotEmpty) pw.Text('Reg. Com: $regCom'),
                      pw.Text('Adresă: $address'),
                      pw.Text('Email: $email'),
                    ],
                  ),
                ),
                pw.SizedBox(height: 40),

                // Items Table
                pw.TableHelper.fromTextArray(
                  headers: ['Nr.', 'Descriere Serviciu', 'U.M.', 'Cantitate', 'Preț Unitar (RON)', 'Valoare (RON)'],
                  data: [
                    ['1', 'Rezervare masă tenis - $venueName ($date, $time)', 'Buc', '1', amount.toStringAsFixed(2), amount.toStringAsFixed(2)],
                    ['2', 'Taxă Platformă PingPong Playhub', 'Buc', '1', '5.00', '5.00'],
                  ],
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                  cellHeight: 30,
                  cellAlignments: {
                    0: pw.Alignment.center,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.center,
                    3: pw.Alignment.center,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.centerRight,
                  },
                ),
                pw.SizedBox(height: 20),

                // Total
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 200,
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border.all(color: PdfColors.grey400),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('TOTAL DE PLATĂ:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text('${(amount + 5.0).toStringAsFixed(2)} RON', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
                
                pw.Spacer(),
                // Footer
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Această factură a fost generată automat și este valabilă fără semnătură și ștampilă conform Codului Fiscal.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'Mulțumim că ați ales PingPong Playhub!',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey800, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );

    // Share the PDF via the printing package (shows system share dialog for email/save)
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Factura_${matchId.substring(0, 6)}.pdf',
    );
  }
}
