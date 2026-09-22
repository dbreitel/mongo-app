import express, { RequestHandler } from 'express';
import { MongoClient, ObjectId } from 'mongodb';
import path from 'path';

const uri = process.env.MONGODB_URI;
if (!uri) throw new Error('MONGODB_URI is not set');

const dbName = process.env.MONGODB_DB ?? 'notesapp';
const port = Number(process.env.PORT ?? 3000);

interface Note {
  title: string;
  body: string;
  createdAt: Date;
}

const client = new MongoClient(uri);
const notes = client.db(dbName).collection<Note>('notes');

const wrap = (fn: RequestHandler): RequestHandler => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);

const app = express();
app.use(express.json({ limit: '64kb' }));
app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/healthz', (_req, res) => {
  res.type('text').send('ok');
});

app.get('/readyz', wrap(async (_req, res) => {
  await client.db(dbName).command({ ping: 1 });
  res.type('text').send('ready');
}));

app.get('/api/notes', wrap(async (_req, res) => {
  res.json(await notes.find().sort({ createdAt: -1 }).limit(200).toArray());
}));

app.post('/api/notes', wrap(async (req, res) => {
  const { title, body } = req.body ?? {};
  // reject non-strings: a {$ne:...} object here would otherwise reach the query layer
  if (typeof title !== 'string' || typeof body !== 'string' || !title.trim()) {
    res.status(400).json({ error: 'title and body must be strings, title is required' });
    return;
  }
  const doc: Note = {
    title: title.trim().slice(0, 200),
    body: body.slice(0, 5000),
    createdAt: new Date(),
  };
  const { insertedId } = await notes.insertOne(doc);
  res.status(201).json({ _id: insertedId, ...doc });
}));

app.delete('/api/notes/:id', wrap(async (req, res) => {
  if (!ObjectId.isValid(req.params.id)) {
    res.status(400).json({ error: 'invalid id' });
    return;
  }
  const { deletedCount } = await notes.deleteOne({ _id: new ObjectId(req.params.id) });
  res.sendStatus(deletedCount ? 204 : 404);
}));

client.connect()
  .then(() => notes.createIndex({ createdAt: -1 }))
  .then(() => app.listen(port, () => console.log(`notes-app listening on :${port}`)))
  .catch((err) => {
    console.error('mongo connect failed', err);
    process.exit(1);
  });
